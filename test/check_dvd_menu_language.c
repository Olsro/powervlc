/* Compile with DVDNAV_MENU_START_SOURCE pointing at patched contrib
 * src/menu_start.c, and the matching libdvdnav internal include directory. */
#include <assert.h>
#include <stdio.h>
#ifndef DVDNAV_MENU_START_SOURCE
#error Define DVDNAV_MENU_START_SOURCE to the patched libdvdnav menu_start.c
#endif
#include DVDNAV_MENU_START_SOURCE

int main(void)
{
    /* Authored default-English / French / Japanese highlight instructions. */
    vm_cmd_t commands[] = {
        {{0x56,0,0,0,0x04,0,0,0}},
        {{0x71,0,0,0,0x66,0x72,0,0}},
        {{0x56,0x20,0,0,0x08,0,0,0x90}},
        {{0x71,0,0,0,0x6a,0x61,0,0}},
        {{0x56,0x20,0,0,0x0c,0,0,0x90}},
    };
    pgc_command_tbl_t table = {0};
    pgc_t pgc = {0};
    vm_t vm = {0};
    pci_t pci = {0};
    registers_t result;
    table.pre_cmds = commands;
    table.nr_of_pre = sizeof(commands) / sizeof(commands[0]);
    pgc.command_tbl = &table;
    vm.state.pgc = &pgc;
    vm.state.registers.SPRM[0] = 0x6672; /* menu French */
    vm.state.registers.SPRM[16] = 0x6a61; /* independent audio preference */
    vm.state.registers.SPRM[18] = 0x6465;
    pci.hli.hl_gi.btngr_ns = 2;
    pci.hli.hl_gi.btn_ns = 3;
    assert(language_button(&vm, &pci, &result) == 2);
    assert(result.SPRM[16] == 0x6a61 && result.SPRM[18] == 0x6465);
    vm.state.registers.SPRM[0] = 0x656e;
    assert(language_button(&vm, &pci, &result) == 1);
    vm.state.registers.SPRM[0] = 0x6a61;
    assert(language_button(&vm, &pci, &result) == 3);
    vm.state.registers.SPRM[0] = 0x6672;

    pci.hli.btnit[19].cmd.bytes[0] = 1; /* aspect groups disagree */
    assert(!language_button(&vm, &pci, &result));
    pci.hli.btnit[19].cmd.bytes[0] = 0;
    pci.hli.hl_gi.fosl_btnn = 1;
    assert(!language_button(&vm, &pci, &result));
    pci.hli.hl_gi.fosl_btnn = 0;
    pci.hli.hl_gi.foac_btnn = 2;
    assert(!language_button(&vm, &pci, &result));
    pci.hli.hl_gi.foac_btnn = 0;
    pci.hli.hl_gi.btn_ofn = 1;
    assert(!language_button(&vm, &pci, &result));
    pci.hli.hl_gi.btn_ofn = 0;
    pci.hli.btnit[1].auto_action_mode = 1;
    assert(!language_button(&vm, &pci, &result));
    pci.hli.btnit[1].auto_action_mode = 0;
    pci.hli.hl_gi.btn_ns = 1; /* desired button outside the NAV */
    assert(!language_button(&vm, &pci, &result));
    pci.hli.hl_gi.btn_ns = 3;

    vm.state.registers.GPRM_mode[0] = 1;
    assert(!language_button(&vm, &pci, &result));
    vm.state.registers.GPRM_mode[0] = 0;
    table.nr_of_pre = 1; /* ordinary menu with an unconditional highlight */
    assert(!language_button(&vm, &pci, &result));
    commands[0] = (vm_cmd_t){{0x78,0,0,0,0,0,0,0}}; /* random */
    assert(!language_button(&vm, &pci, &result));
    commands[0] = (vm_cmd_t){{0,1,0,0,0,0,0,1}}; /* backwards goto */
    assert(!language_button(&vm, &pci, &result));
    commands[0] = (vm_cmd_t){{0x40,3,0,0,0,0,0,0}}; /* counter */
    assert(!language_button(&vm, &pci, &result));
    assert(!dvdnav_start_menu(NULL));
    puts("DVD menu language guards passed");
    return 0;
}
