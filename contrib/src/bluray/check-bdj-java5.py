#!/usr/bin/env python3
"""Check that the libbluray BD-J jars can run on a Java 5 JRE.

check-bdj-java6.py answers the question "does anything here postdate Java 6?"
using the JDK's ct.sym. It cannot be pointed at Java 5: no JDK ever shipped
ct.sym data for release 5 (the oldest is 6), so the Java 5 floor can only be
verified against a real Java 5 platform.

That platform cannot be vendored the way contrib/java6-bootclasspath holds
OpenJDK 6's rt.jar -- OpenJDK started at Java 6, and Apache Harmony or GNU
Classpath reimplement the platform without the Sun internals the BD-J layer
plugs into. So what is committed instead is an API *index* extracted from a
real Java 5 JRE by make-java5-api-index.py: class names, hierarchy and member
descriptors, no implementation. See contrib/java5-api/README.

    check-bdj-java5.py --api-index INDEX.txt.gz JAR [JAR...]

--runtime is still accepted, to check straight against a Java 5 JRE's jars
when one happens to be at hand.

The jars are deliberately compiled against a Java 6 rt.jar, because the
compatibility methods added by 0004-bdj-run-on-java-5.patch must see the Java 6
shapes of the JDK internals they sit next to. That leaves a known, closed set of
Java 6 references inside methods that a Java 5 VM never dispatches to; they are
listed in ALLOWED below and everything else is an error.
"""

import argparse
import gzip
import importlib.util
import os
import sys

# Reuse the class file / jar readers rather than duplicating them. Loading a
# module by path makes CPython cache a .pyc next to it, which would drop a
# __pycache__ into the source tree on every build; the sibling script is tiny,
# so byte compilation is switched off around the import rather than leaving
# build droppings behind.
_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    'check_bdj_java6', os.path.join(_HERE, 'check-bdj-java6.py'))
_j6 = importlib.util.module_from_spec(_spec)
_no_bytecode = sys.dont_write_bytecode
sys.dont_write_bytecode = True
try:
    _spec.loader.exec_module(_j6)
finally:
    sys.dont_write_bytecode = _no_bytecode


# References that only exist from Java 6 on and are unreachable on a Java 5 VM.
# Each is reached from a method that Java 5's version of the class it overrides
# simply does not declare, so the VM never resolves the descriptor.
ALLOWED = {
    # BDToolkit implements the Java 6 Toolkit surface. Java 5's Toolkit
    # declares none of these, so they are never called there.
    'java/awt/Dialog$ModalExclusionType',
    'java/awt/Dialog$ModalityType',
    # BDFileSystemImpl keeps the Java 6 shapes alongside the Java 5 ones; only
    # the ones matching the running JDK are ever dispatched to.
    'java/io/FileSystem.checkAccess(Ljava/io/File;I)Z',
    'java/io/FileSystem.getSpace(Ljava/io/File;I)J',
    'java/io/FileSystem.setPermission(Ljava/io/File;IZZ)Z',
    # Focus-cause plumbing, lazily linked; upstream already treats these as
    # such for the Java 6 check (KNOWN_LAZY_REFS there).
    'java/awt/event/FocusEvent$Cause',
    'sun/awt/CausedFocusEvent',
    'sun/awt/CausedFocusEvent$Cause',
}


class _Entry:
    """Duck-types ClassFile for find_member: hierarchy plus member sets."""

    __slots__ = ('super', 'interfaces', 'fields', 'methods')

    def __init__(self, superclass, interfaces):
        self.super = superclass
        self.interfaces = interfaces
        self.fields = set()
        self.methods = set()


class ApiIndex:
    """The committed Java 5 API index, in the format make-java5-api-index.py
    writes: 'C <class> <super|-> <ifaces>' followed by its 'F'/'M' members."""

    def __init__(self, path):
        self.classes = {}
        opener = gzip.open if path.endswith('.gz') else open
        current = None
        with opener(path, 'rt', encoding='utf-8') as fh:
            for line in fh:
                line = line.rstrip('\n')
                if not line or line.startswith('#'):
                    continue
                kind, rest = line[0], line[2:]
                if kind == 'C':
                    parts = rest.split(' ')
                    name = parts[0]
                    superclass = parts[1] if len(parts) > 1 else '-'
                    ifaces = parts[2] if len(parts) > 2 else ''
                    current = _Entry(None if superclass == '-' else superclass,
                                     [i for i in ifaces.split(',') if i])
                    self.classes[name] = current
                elif current is not None:
                    name, _, desc = rest.partition(' ')
                    (current.fields if kind == 'F'
                     else current.methods).add((name, desc))

    def __contains__(self, name):
        return name in self.classes

    def parse(self, name):
        return self.classes.get(name)

    def __len__(self):
        return len(self.classes)


def _size(source):
    """Class count, for either an ApiIndex or check-bdj-java6's JarIndex."""
    return len(getattr(source, 'classes', None) or source.where)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('jars', nargs='+', metavar='JAR')
    parser.add_argument('--api-index', default=None, metavar='FILE',
                        help='committed Java 5 API index (.txt or .txt.gz)')
    parser.add_argument('--runtime', default=[], action='append',
                        metavar='JAR',
                        help='a jar of a real Java 5 class library. Repeatable.')
    args = parser.parse_args()

    if not args.api_index and not args.runtime:
        parser.error('need --api-index or at least one --runtime')

    own = _j6.load_jars(args.jars)
    sources = []
    if args.api_index:
        sources.append(ApiIndex(args.api_index))
    if args.runtime:
        sources.append(_j6.JarIndex(args.runtime))

    def resolve(name):
        found = own.get(name)
        if found is not None:
            return found
        for source in sources:
            found = source.parse(name)
            if found is not None:
                return found
        return None

    missing_classes, missing_members, allowed_hits = set(), set(), set()
    for cf in own.values():
        classes, members = cf.references()
        for name in classes:
            if name.startswith('[') or resolve(name):
                continue
            (allowed_hits if name in ALLOWED else missing_classes).add(name)
        for is_field, owner, name, desc in members:
            if owner.startswith('[') or owner in own:
                continue
            if not resolve(owner):
                continue                   # reported through its class already
            if _j6.find_member(resolve, owner, is_field, name, desc):
                continue
            entry = '%s.%s%s' % (owner, name, '' if is_field else desc)
            (allowed_hits if entry in ALLOWED
             else missing_members).add(entry)

    print('checked %d classes from %d jar(s) against the Java 5 API '
          '(%d classes)'
          % (len(own), len(args.jars), sum(_size(s) for s in sources)))
    if allowed_hits:
        print('\nPost-Java 5 references that a Java 5 VM never reaches '
              '(known and accepted):')
        for entry in sorted(allowed_hits):
            print('  %s' % entry)

    if not missing_classes and not missing_members:
        print('\nOK: nothing else requires Java 6.')
        return 0

    print('\nERROR: these are absent from Java 5 and are NOT in the accepted '
          'set, so BD-J would fail at runtime on Mac OS X 10.4/10.5:')
    for entry in sorted(missing_classes):
        print('  class  %s' % entry)
    for entry in sorted(missing_members):
        print('  member %s' % entry)
    print('\nEither add the Java 5 equivalent (see '
          '0004-bdj-run-on-java-5.patch) or, if the reference really is '
          'unreachable on Java 5, add it to ALLOWED in this script.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
