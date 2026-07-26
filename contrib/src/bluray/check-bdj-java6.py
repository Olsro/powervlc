#!/usr/bin/env python3
"""Check that the libbluray BD-J jars only use APIs that exist in Java 6.

Compiling with -source/-target 6 pins the bytecode version but does NOT stop
javac from linking against APIs added after Java 6: those only blow up at
runtime, on the old machines, as NoSuchMethodError/NoClassDefFoundError. This
script closes that hole without needing a Java 6 rt.jar: it reads every class
reference, method reference and field reference out of the jars' constant pools
and resolves them against the Java 6 API signatures shipped in the JDK's own
ct.sym (which records the API of every release from 6 up).

Usage:
    check-bdj-java6.py [--ct-sym PATH] [--release 6] JAR [JAR...]

ct.sym only describes the documented API, so "absent from release 6" alone
would flag every package-private JDK class the BD-J AWT replacement legitimately
touches. A reference is therefore only an error when it is absent from the
target release *and* present in a later one, which is what an API added after
Java 6 looks like. Anything absent from every release is undocumented internals
and is reported separately: only a real JRE of that vintage can confirm those.
"""

import argparse
import os
import struct
import sys
import zipfile

# Constant pool tags we need to walk.
CP_UTF8, CP_INT, CP_FLOAT, CP_LONG, CP_DOUBLE = 1, 3, 4, 5, 6
CP_CLASS, CP_STRING, CP_FIELDREF, CP_METHODREF = 7, 8, 9, 10
CP_IFACEMETHODREF, CP_NAMEANDTYPE = 11, 12
CP_METHODHANDLE, CP_METHODTYPE, CP_DYNAMIC = 15, 16, 17
CP_INVOKEDYNAMIC, CP_MODULE, CP_PACKAGE = 18, 19, 20

# Tag -> fixed payload size, for the tags whose contents we skip over.
_FIXED = {CP_INT: 4, CP_FLOAT: 4, CP_LONG: 8, CP_DOUBLE: 8, CP_CLASS: 2,
          CP_STRING: 2, CP_FIELDREF: 4, CP_METHODREF: 4, CP_IFACEMETHODREF: 4,
          CP_NAMEANDTYPE: 4, CP_METHODHANDLE: 3, CP_METHODTYPE: 2,
          CP_DYNAMIC: 4, CP_INVOKEDYNAMIC: 4, CP_MODULE: 2, CP_PACKAGE: 2}


class ClassFile:
    """Just enough of a class file parser: constant pool, hierarchy, members."""

    def __init__(self, data):
        if data[:4] != b'\xca\xfe\xba\xbe':
            raise ValueError('not a class file')
        self.cp = {}
        pos = 10
        count = struct.unpack_from('>H', data, 8)[0]
        i = 1
        while i < count:
            tag = data[pos]
            pos += 1
            if tag == CP_UTF8:
                length = struct.unpack_from('>H', data, pos)[0]
                self.cp[i] = data[pos + 2:pos + 2 + length].decode(
                    'utf-8', 'replace')
                pos += 2 + length
            else:
                size = _FIXED.get(tag)
                if size is None:
                    raise ValueError('unknown constant pool tag %d' % tag)
                self.cp[i] = (tag,) + struct.unpack_from(
                    '>' + 'H' * (size // 2) if size % 2 == 0 else '>BH',
                    data, pos)
                pos += size
            # longs and doubles eat two constant pool slots.
            i += 2 if tag in (CP_LONG, CP_DOUBLE) else 1
        self._data = data
        self._cp_end = pos

        pos += 2                                        # access_flags
        self.name = self._class_name(struct.unpack_from('>H', data, pos)[0])
        pos += 2
        super_idx = struct.unpack_from('>H', data, pos)[0]
        self.super = self._class_name(super_idx) if super_idx else None
        pos += 2
        n_ifaces = struct.unpack_from('>H', data, pos)[0]
        pos += 2
        self.interfaces = [self._class_name(
            struct.unpack_from('>H', data, pos + 2 * k)[0])
            for k in range(n_ifaces)]
        pos += 2 * n_ifaces

        self.fields, self.methods = set(), set()
        for target in (self.fields, self.methods):
            n = struct.unpack_from('>H', data, pos)[0]
            pos += 2
            for _ in range(n):
                name = self.cp[struct.unpack_from('>H', data, pos + 2)[0]]
                desc = self.cp[struct.unpack_from('>H', data, pos + 4)[0]]
                target.add((name, desc))
                pos = self._skip_attributes(pos + 6)

    def _skip_attributes(self, pos):
        n = struct.unpack_from('>H', self._data, pos)[0]
        pos += 2
        for _ in range(n):
            length = struct.unpack_from('>I', self._data, pos + 2)[0]
            pos += 6 + length
        return pos

    def _class_name(self, idx):
        return self.cp[self.cp[idx][1]]

    def references(self):
        """(classes, members) referenced from the constant pool."""
        classes, members = set(), set()
        for entry in self.cp.values():
            if isinstance(entry, str):
                continue
            tag = entry[0]
            if tag == CP_CLASS:
                classes.add(self.cp[entry[1]])
            elif tag in (CP_FIELDREF, CP_METHODREF, CP_IFACEMETHODREF):
                owner = self._class_name(entry[1])
                nat = self.cp[entry[2]]
                members.add((tag == CP_FIELDREF, owner,
                             self.cp[nat[1]], self.cp[nat[2]]))
        return classes, members


def load_jars(paths):
    """name -> ClassFile for every class shipped by the jars themselves."""
    classes = {}
    for path in paths:
        with zipfile.ZipFile(path) as zf:
            for entry in zf.namelist():
                if entry.endswith('.class'):
                    cf = ClassFile(zf.read(entry))
                    classes[cf.name] = cf
    return classes


class JarIndex:
    """Lazily parsed view of a real runtime's class library."""

    def __init__(self, paths):
        self.where = {}                    # class name -> (zipfile, entry)
        self._parsed = {}
        for path in paths:
            zf = zipfile.ZipFile(path)
            for entry in zf.namelist():
                if entry.endswith('.class'):
                    self.where.setdefault(entry[:-len('.class')], (zf, entry))

    def __contains__(self, name):
        return name in self.where

    def parse(self, name):
        if name not in self._parsed:
            found = self.where.get(name)
            try:
                self._parsed[name] = ClassFile(found[0].read(found[1])) \
                    if found else None
            except ValueError:
                self._parsed[name] = None
        return self._parsed[name]


def _entry_class_name(rest):
    """Path inside a ct.sym release directory -> class name."""
    # JDK 9+ releases insert the module name, which is the only segment that
    # can contain a dot, before the package path.
    head, _, tail = rest.partition('/')
    if '.' in head and tail:
        rest = tail
    return rest[:-len('.sig')]


class CtSym:
    """Release-aware view of the JDK's API signature archive."""

    def __init__(self, path, release):
        self.zf = zipfile.ZipFile(path)
        self.target = {}                   # name -> zip entry, target release
        self.later = {}                    # name -> zip entry, any newer one
        for entry in self.zf.namelist():
            if not entry.endswith('.sig'):
                continue
            head, _, rest = entry.partition('/')
            if head.endswith('-modules'):
                continue
            name = _entry_class_name(rest)
            if release in head:
                self.target[name] = entry
            elif head > release:           # release chars sort chronologically
                self.later.setdefault(name, entry)
        self._parsed = {}

    def parse(self, name, table):
        entry = table.get(name)
        if entry is None:
            return None
        if entry not in self._parsed:
            try:
                self._parsed[entry] = ClassFile(self.zf.read(entry))
            except ValueError:
                self._parsed[entry] = None
        return self._parsed[entry]


def find_member(resolve, owner, is_field, name, desc):
    """Walk the hierarchy looking for a declared member."""
    seen, todo = set(), [owner]
    while todo:
        current = todo.pop()
        if current in seen:
            continue
        seen.add(current)
        cf = resolve(current)
        if cf is None:
            continue
        if (name, desc) in (cf.fields if is_field else cf.methods):
            return True
        if cf.super:
            todo.append(cf.super)
        todo.extend(cf.interfaces)
        # Interfaces implicitly expose java.lang.Object's methods.
        if not is_field:
            todo.append('java/lang/Object')
    return False


# References that do postdate the target release but are reached only through
# lazy linking, so the old JVM never resolves them. Keep the justification with
# the entry: anything listed here is a hole in the guarantee.
KNOWN_LAZY_REFS = {
    # BDFramePeer declares requestFocus() twice, once taking the Java <= 8
    # sun.awt.CausedFocusEvent.Cause and once the Java 9+ FocusEvent.Cause, and
    # lets the JVM link whichever java.awt.peer.FramePeer actually calls. The
    # unused overload's parameter type is never loaded. Upstream ships a build
    # -time stub for it and excludes it from the jar on purpose.
    'java/awt/event/FocusEvent$Cause',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('jars', nargs='+', metavar='JAR')
    parser.add_argument('--release', default='6',
                        help='target release character (default: 6)')
    parser.add_argument('--ct-sym', default=None,
                        help='path to ct.sym (default: $JAVA_HOME/lib/ct.sym)')
    parser.add_argument('--runtime', default=[], action='append',
                        metavar='JAR',
                        help='class library of a real JRE of the target '
                             'vintage; settles the references ct.sym cannot '
                             'describe. Repeatable.')
    args = parser.parse_args()

    ct_sym = args.ct_sym
    if not ct_sym:
        java_home = os.environ.get('JAVA_HOME', '')
        ct_sym = os.path.join(java_home, 'lib', 'ct.sym')
    if not os.path.exists(ct_sym):
        sys.exit('cannot find ct.sym (%s); set JAVA_HOME or pass --ct-sym'
                 % ct_sym)

    own = load_jars(args.jars)
    ct = CtSym(ct_sym, args.release)
    if not ct.target:
        sys.exit('ct.sym holds no data for release %s; use a JDK that still '
                 'supports it (JDK 11 covers 6 to 11)' % args.release)

    runtime = JarIndex(args.runtime) if args.runtime else None

    def in_target(name):
        return own.get(name) or ct.parse(name, ct.target)

    def in_runtime(name):
        # The real class library first: ct.sym stops at the documented API, so
        # its version of a class hides the package-private members we are
        # precisely trying to confirm.
        return (own.get(name) or (runtime.parse(name) if runtime else None)
                or ct.parse(name, ct.target))

    def in_later(name):
        return (own.get(name) or ct.parse(name, ct.later)
                or ct.parse(name, ct.target))

    too_new, undocumented, lazy, confirmed = set(), set(), set(), set()
    for cf in own.values():
        classes, members = cf.references()
        for name in classes:
            if name.startswith('[') or in_target(name):
                continue
            if name in KNOWN_LAZY_REFS:
                lazy.add('class  %s' % name)
            elif runtime and name in runtime:
                confirmed.add('class  %s' % name)
            elif name in ct.later:
                too_new.add('class  %s' % name)
            else:
                undocumented.add('class  %s' % name)
        for is_field, owner, name, desc in members:
            if owner.startswith('[') or owner in own:
                continue
            if not in_target(owner) and not (runtime and owner in runtime) \
                    and owner not in ct.later:
                continue                   # reported through its class already
            if find_member(in_target, owner, is_field, name, desc):
                continue
            entry = 'member %s.%s%s' % (owner, name, '' if is_field else desc)
            key = '%s.%s' % (owner, name)
            if key in KNOWN_LAZY_REFS or owner in KNOWN_LAZY_REFS:
                lazy.add(entry)
            elif runtime and find_member(in_runtime, owner, is_field,
                                         name, desc):
                confirmed.add(entry)
            elif find_member(in_later, owner, is_field, name, desc):
                too_new.add(entry)
            else:
                undocumented.add(entry)

    print('checked %d classes from %d jar(s) against the Java %s API '
          '(%d classes in ct.sym%s)'
          % (len(own), len(args.jars), args.release, len(ct.target),
             ', %d in the archived runtime' % len(runtime.where)
             if runtime else ''))

    if lazy:
        print('\nPost-Java %s references reached only through lazy linking '
              '(known and accepted):' % args.release)
        for entry in sorted(lazy):
            print('  %s' % entry)

    if confirmed:
        classes = sorted(e for e in confirmed if e.startswith('class'))
        members = len(confirmed) - len(classes)
        print('\nUndocumented by ct.sym but present in the archived Java %s '
              'runtime:' % args.release)
        for entry in classes:
            print('  %s' % entry)
        if members:
            print('  ... and %d member reference(s) on those internals'
                  % members)

    if undocumented and not runtime:
        print('\nUndocumented in every release, so unverifiable without a real '
              'Java %s class library (pass --runtime):' % args.release)
        for entry in sorted(undocumented):
            print('  %s' % entry)
        undocumented = set()               # informational only in this mode

    if not too_new and not undocumented:
        print('\nOK: nothing added after Java %s is referenced' % args.release)
        return 0

    if too_new:
        print('\nFAIL: added after Java %s, so absent from the target JRE:'
              % args.release)
        for entry in sorted(too_new):
            print('  %s' % entry)
    if undocumented:
        print('\nFAIL: found neither in the Java %s API nor in the archived '
              'Java %s runtime:' % (args.release, args.release))
        for entry in sorted(undocumented):
            print('  %s' % entry)
    return 1


if __name__ == '__main__':
    sys.exit(main())
