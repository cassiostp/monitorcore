Read the project-wide rules first: https://github.com/cassiostp/tangcore/blob/main/AGENTS.md

# monitorcore — menu FPGA design

The menu's own FPGA design: loaded from flash on power-up and as `monitor.bin` when the firmware leaves a game core. No game, no SDRAM, no scrolling — just controllers, USB HID, HDMI text and the BL616 link.

## Layout

- Top: `src/monitor_top.v` (`module monitor_top`); text/video `src/monitor2hdmi.v` into `src/hdmi/hdmi.sv` (+ serializer/TMDS/packet/audio helpers, Sameer Puri HDMI v1.4a).
- No memory controller: the only BRAM is the char/font/logo `gowin_dpb_menu` behind `src/iosys/textdisp.v`.
- iosys: `src/iosys/iosys_bl616.v` (`CORE_ID(0)` in `src/monitor_top.v`; `CONF_STR` is the menu OSD string) plus `textdisp.v`, `gowin_dpb_menu.v`, `uart_fixed.v`. `uart_fractional.v`/`uart_integer.v` exist but are not in the build. This is one of six divergent copies (`cassiostp/tangcore#30`): a fix to one usually belongs in the others.
- PLLs: `src/pll/` (138K `PLL`: `pll_27/74/12.v`), `src/plla/` (60K `PLLA`), `src/pllr/gowin_pll_hdmi.v` (nano `rPLL`).
- Boards `src/boards/`: `console*.v` (DS2 + USB1/USB2) share `console.cst`; `mega60k.v`/`mega138k.v`, `primer25k.v`, `nano20k.v` each with their own cst. `console60k_snescontroller.v` is unused by `build.tcl`.

## Building

```tcl
gw_sh build.tcl <device>   # nano20k primer25k mega60k mega138k mega138k_31002 console60k console138k
```

CI builds it like the game cores:

```sh
gh workflow run cores.yml -R cassiostp/tangcore --ref ci/core-builds -f core=monitorcore -f ref=<branch> -f board=console138k
```

`build.tcl` has no SDC (`-type sdc` never appears): clocks come from the PLL IP only. Its nano20k CST path (`src/nano20k/monitor.cst`) does not exist on disk; the file is `src/boards/nano20k.cst`.

## Clocks

- GW5 boards: `sys_clk` 50 MHz in, `FREQ=50_000_000`; `pll_27` 50 -> 27 MHz, `pll_74` 27 -> 74.25 MHz pixel + 371.25 MHz serial; `pll_12` 50 -> 12 MHz USB (`monitor_top.v`).
- Nano: `sys_clk` 27 MHz direct, `FREQ=27_000_000`, `rPLL` 27 -> 371.25 MHz + `CLKDIV /5`.
- Video is fixed 1280x720@60 (`monitor2hdmi.v`: 1650x750 total, `VIDEO_ID_CODE 4`); UART is 2 Mbaud (`CLK_FREQ`/`BAUD` in `iosys_bl616.v`).

## Inputs

- Controllers: `controller_snes.v` always built; `controller_ds2.sv` + `dualshock_controller.v` under `CONTROLLER_DS2`; USB HID (`usb_hid_host.v` + `usb_hid_host_rom.hex`) under `USB1`/`USB2` on primer/console boards only (`monitor_top.v`, `build.tcl`).
- The firmware link carries joystick/pad bytes back to the MCU; the menu OSD string is `CONF_STR` in `src/iosys/iosys_bl616.v`.

## Simulations

`test/tb_sys.v` (+ `tb_sys.sh`/`tb_sys.bat`) drives a stale `sys` module, not `monitor_top`/`iosys_bl616`, with the pre-framed raw-UART commands; `src/sys/` does not exist, so it does not run against this tree.
