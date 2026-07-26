# PL source interface

The Vivado Block Design is repository-managed by `scripts/ps_pl_bram.tcl` and
contains only the Zynq PS, AXI infrastructure, two AXI BRAM controllers, two
true dual-port BRAMs, and reset logic. DDS, acquisition control, and FIR logic
must remain ordinary RTL outside the BD.

The BD exports two native BRAM Port B interfaces:

| Interface | Owner | Direction |
| --- | --- | --- |
| `MEAS_BRAM_PL` | Application measurement RTL | PL writes, PS reads |
| `COEFF_BRAM_PL` | Application FIR/configuration RTL | PS writes, PL reads |

Both exported interfaces use the BMG's 32-bit **byte address** convention so
they match AXI BRAM Controller addressing. The SystemVerilog package expresses
header positions as word indices; application RTL must shift a word index left
by two bits when driving `*_BRAM_PL_addr`.

Protocol sources:

| File | Purpose |
| --- | --- |
| `hdl/shared_bram_protocol_pkg.sv` | Shared PL constants and word addresses |

All status fields use zero as `BUSY`. A cleared BRAM, an asserted reset, or an
uninitialized PS therefore cannot be interpreted as a valid transaction.
Consumers must additionally validate `MAGIC`, `VERSION`, payload bounds,
format, and a stable `GENERATION` before accepting data.

The infrastructure wrapper only exports the native BRAM signals. Application
RTL decides when and how to read or write them. No generic BRAM writer or
loader FSM is included, and application modules must not be added to the BD as
module references. See `doc/PS端共享BRAM访问与STATUS通知协议.md` for the PS access
and polling procedure.
