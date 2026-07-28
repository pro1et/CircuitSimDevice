// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2022.2 (win64) Build 3671981 Fri Oct 14 05:00:03 MDT 2022
// Date        : Tue Jul 28 12:33:59 2026
// Host        : DESKTOP-3MP1EO2 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               e:/Vivado/FPGA_project/CircuitSimDevice/fpga/src/ip/coef_bram/coef_bram_ip/coef_bram_ip_sim_netlist.v
// Design      : coef_bram_ip
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7z020clg400-2
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "coef_bram_ip,blk_mem_gen_v8_4_5,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_5,Vivado 2022.2" *) 
(* NotValidForBitStream *)
module coef_bram_ip
   (clka,
    rsta,
    ena,
    wea,
    addra,
    dina,
    douta,
    clkb,
    rstb,
    enb,
    web,
    addrb,
    dinb,
    doutb);
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTA, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clka;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA RST" *) input rsta;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA EN" *) input ena;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA WE" *) input [3:0]wea;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *) input [9:0]addra;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *) input [31:0]dina;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DOUT" *) output [31:0]douta;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTB, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clkb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB RST" *) input rstb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB EN" *) input enb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB WE" *) input [3:0]web;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB ADDR" *) input [9:0]addrb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DIN" *) input [31:0]dinb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DOUT" *) output [31:0]doutb;

  wire [9:0]addra;
  wire [9:0]addrb;
  wire clka;
  wire clkb;
  wire [31:0]dina;
  wire [31:0]dinb;
  wire [31:0]douta;
  wire [31:0]doutb;
  wire ena;
  wire enb;
  wire rsta;
  wire rstb;
  wire [3:0]wea;
  wire [3:0]web;
  wire NLW_U0_dbiterr_UNCONNECTED;
  wire NLW_U0_rsta_busy_UNCONNECTED;
  wire NLW_U0_rstb_busy_UNCONNECTED;
  wire NLW_U0_s_axi_arready_UNCONNECTED;
  wire NLW_U0_s_axi_awready_UNCONNECTED;
  wire NLW_U0_s_axi_bvalid_UNCONNECTED;
  wire NLW_U0_s_axi_dbiterr_UNCONNECTED;
  wire NLW_U0_s_axi_rlast_UNCONNECTED;
  wire NLW_U0_s_axi_rvalid_UNCONNECTED;
  wire NLW_U0_s_axi_sbiterr_UNCONNECTED;
  wire NLW_U0_s_axi_wready_UNCONNECTED;
  wire NLW_U0_sbiterr_UNCONNECTED;
  wire [9:0]NLW_U0_rdaddrecc_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_bid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_bresp_UNCONNECTED;
  wire [9:0]NLW_U0_s_axi_rdaddrecc_UNCONNECTED;
  wire [31:0]NLW_U0_s_axi_rdata_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_rid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_rresp_UNCONNECTED;

  (* C_ADDRA_WIDTH = "10" *) 
  (* C_ADDRB_WIDTH = "10" *) 
  (* C_ALGORITHM = "1" *) 
  (* C_AXI_ID_WIDTH = "4" *) 
  (* C_AXI_SLAVE_TYPE = "0" *) 
  (* C_AXI_TYPE = "1" *) 
  (* C_BYTE_SIZE = "8" *) 
  (* C_COMMON_CLK = "0" *) 
  (* C_COUNT_18K_BRAM = "0" *) 
  (* C_COUNT_36K_BRAM = "1" *) 
  (* C_CTRL_ECC_ALGO = "NONE" *) 
  (* C_DEFAULT_DATA = "0" *) 
  (* C_DISABLE_WARN_BHV_COLL = "0" *) 
  (* C_DISABLE_WARN_BHV_RANGE = "0" *) 
  (* C_ELABORATION_DIR = "./" *) 
  (* C_ENABLE_32BIT_ADDRESS = "0" *) 
  (* C_EN_DEEPSLEEP_PIN = "0" *) 
  (* C_EN_ECC_PIPE = "0" *) 
  (* C_EN_RDADDRA_CHG = "0" *) 
  (* C_EN_RDADDRB_CHG = "0" *) 
  (* C_EN_SAFETY_CKT = "0" *) 
  (* C_EN_SHUTDOWN_PIN = "0" *) 
  (* C_EN_SLEEP_PIN = "0" *) 
  (* C_EST_POWER_SUMMARY = "Estimated Power for IP     :     6.2874 mW" *) 
  (* C_FAMILY = "zynq" *) 
  (* C_HAS_AXI_ID = "0" *) 
  (* C_HAS_ENA = "1" *) 
  (* C_HAS_ENB = "1" *) 
  (* C_HAS_INJECTERR = "0" *) 
  (* C_HAS_MEM_OUTPUT_REGS_A = "0" *) 
  (* C_HAS_MEM_OUTPUT_REGS_B = "0" *) 
  (* C_HAS_MUX_OUTPUT_REGS_A = "0" *) 
  (* C_HAS_MUX_OUTPUT_REGS_B = "0" *) 
  (* C_HAS_REGCEA = "0" *) 
  (* C_HAS_REGCEB = "0" *) 
  (* C_HAS_RSTA = "1" *) 
  (* C_HAS_RSTB = "1" *) 
  (* C_HAS_SOFTECC_INPUT_REGS_A = "0" *) 
  (* C_HAS_SOFTECC_OUTPUT_REGS_B = "0" *) 
  (* C_INITA_VAL = "0" *) 
  (* C_INITB_VAL = "0" *) 
  (* C_INIT_FILE = "coef_bram_ip.mem" *) 
  (* C_INIT_FILE_NAME = "coef_bram_ip.mif" *) 
  (* C_INTERFACE_TYPE = "0" *) 
  (* C_LOAD_INIT_FILE = "1" *) 
  (* C_MEM_TYPE = "2" *) 
  (* C_MUX_PIPELINE_STAGES = "0" *) 
  (* C_PRIM_TYPE = "1" *) 
  (* C_READ_DEPTH_A = "1024" *) 
  (* C_READ_DEPTH_B = "1024" *) 
  (* C_READ_LATENCY_A = "1" *) 
  (* C_READ_LATENCY_B = "1" *) 
  (* C_READ_WIDTH_A = "32" *) 
  (* C_READ_WIDTH_B = "32" *) 
  (* C_RSTRAM_A = "0" *) 
  (* C_RSTRAM_B = "0" *) 
  (* C_RST_PRIORITY_A = "CE" *) 
  (* C_RST_PRIORITY_B = "CE" *) 
  (* C_SIM_COLLISION_CHECK = "ALL" *) 
  (* C_USE_BRAM_BLOCK = "0" *) 
  (* C_USE_BYTE_WEA = "1" *) 
  (* C_USE_BYTE_WEB = "1" *) 
  (* C_USE_DEFAULT_DATA = "1" *) 
  (* C_USE_ECC = "0" *) 
  (* C_USE_SOFTECC = "0" *) 
  (* C_USE_URAM = "0" *) 
  (* C_WEA_WIDTH = "4" *) 
  (* C_WEB_WIDTH = "4" *) 
  (* C_WRITE_DEPTH_A = "1024" *) 
  (* C_WRITE_DEPTH_B = "1024" *) 
  (* C_WRITE_MODE_A = "READ_FIRST" *) 
  (* C_WRITE_MODE_B = "READ_FIRST" *) 
  (* C_WRITE_WIDTH_A = "32" *) 
  (* C_WRITE_WIDTH_B = "32" *) 
  (* C_XDEVICEFAMILY = "zynq" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  coef_bram_ip_blk_mem_gen_v8_4_5 U0
       (.addra(addra),
        .addrb(addrb),
        .clka(clka),
        .clkb(clkb),
        .dbiterr(NLW_U0_dbiterr_UNCONNECTED),
        .deepsleep(1'b0),
        .dina(dina),
        .dinb(dinb),
        .douta(douta),
        .doutb(doutb),
        .eccpipece(1'b0),
        .ena(ena),
        .enb(enb),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0),
        .rdaddrecc(NLW_U0_rdaddrecc_UNCONNECTED[9:0]),
        .regcea(1'b0),
        .regceb(1'b0),
        .rsta(rsta),
        .rsta_busy(NLW_U0_rsta_busy_UNCONNECTED),
        .rstb(rstb),
        .rstb_busy(NLW_U0_rstb_busy_UNCONNECTED),
        .s_aclk(1'b0),
        .s_aresetn(1'b0),
        .s_axi_araddr({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arburst({1'b0,1'b0}),
        .s_axi_arid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arlen({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arready(NLW_U0_s_axi_arready_UNCONNECTED),
        .s_axi_arsize({1'b0,1'b0,1'b0}),
        .s_axi_arvalid(1'b0),
        .s_axi_awaddr({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awburst({1'b0,1'b0}),
        .s_axi_awid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awlen({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awready(NLW_U0_s_axi_awready_UNCONNECTED),
        .s_axi_awsize({1'b0,1'b0,1'b0}),
        .s_axi_awvalid(1'b0),
        .s_axi_bid(NLW_U0_s_axi_bid_UNCONNECTED[3:0]),
        .s_axi_bready(1'b0),
        .s_axi_bresp(NLW_U0_s_axi_bresp_UNCONNECTED[1:0]),
        .s_axi_bvalid(NLW_U0_s_axi_bvalid_UNCONNECTED),
        .s_axi_dbiterr(NLW_U0_s_axi_dbiterr_UNCONNECTED),
        .s_axi_injectdbiterr(1'b0),
        .s_axi_injectsbiterr(1'b0),
        .s_axi_rdaddrecc(NLW_U0_s_axi_rdaddrecc_UNCONNECTED[9:0]),
        .s_axi_rdata(NLW_U0_s_axi_rdata_UNCONNECTED[31:0]),
        .s_axi_rid(NLW_U0_s_axi_rid_UNCONNECTED[3:0]),
        .s_axi_rlast(NLW_U0_s_axi_rlast_UNCONNECTED),
        .s_axi_rready(1'b0),
        .s_axi_rresp(NLW_U0_s_axi_rresp_UNCONNECTED[1:0]),
        .s_axi_rvalid(NLW_U0_s_axi_rvalid_UNCONNECTED),
        .s_axi_sbiterr(NLW_U0_s_axi_sbiterr_UNCONNECTED),
        .s_axi_wdata({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_wlast(1'b0),
        .s_axi_wready(NLW_U0_s_axi_wready_UNCONNECTED),
        .s_axi_wstrb({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_wvalid(1'b0),
        .sbiterr(NLW_U0_sbiterr_UNCONNECTED),
        .shutdown(1'b0),
        .sleep(1'b0),
        .wea(wea),
        .web(web));
endmodule
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2022.2"
`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
VHPlDkoDlWlBfBMvPBmGYmaek3s9hXXhjF28kllYPnaNm3TSnzzpXHWHc8Ye9/2L2yiQfJ1hTWou
Ia/zeQ8h9/dtr6QB5YkyW4wlb/LbMgXb+DGIXPSllNl0IMsRQIcQDbcQm1bO/nlhb+2pjxiuaQrl
DbvxoDwPs7z3LunRxsg=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
lmIhoX8hXuc7tNV1sXY1K2/gXL7Y7Hq73qQF7+x03UWWTRd3uhGmVQtOMVbhIW+66UkWUHiD26zL
fzqGor8bgSNGpSFyS11k4TwLQT4OfAMGO8C9Qmmh4+VENBnpS9TW+wHzCv8oUwht7xYtYRZvOvYK
F3fMppz2sBkUd1lciw98ZE/UmNkhqBuMfIYF43j45DEJ55PBhOZNg91Ls4v3qBHyBAaYPFFoMry3
d5Fw1PZyFQSEOSSpwgyds2aN0g6oIwl7zm0LJrM9VDAOxBUE50hk+oHr4jj8J8UhHQJnlEHm1Idm
rvxKygNKRvfSpa90NYxZJFYgqnrMYg+19+9aZA==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
VkyCjO2onoeZWEoYQ/4ue7X5mkHyTYVW9xjdoTsGS4GdP/Q64VaCZL/jr6R8DVDXPMnH7tRMrDpo
jpYBnyzSgOkfgqM+96ioC2fDyAaG4gYgGLmrBR6qK3/mxXwAZZX+GJ9R/eWXkc9h8xN+gsSSX6/M
jIQCgeT6q7PB4dWT6KY=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Iub91V+TnhVlZCSLu6iKmFjix71y6/l83OPTs8uewWvkE7WcqYxEKi9fonXEkzAtWzuKwEUqnOlN
VBsNJqPUdKcd22q523mrdt89mpdosWD+hvZdO7ELhJniY5u9h49FFkubpN2JiUTcIcKEYxVNlds4
wyvaYUqbPVH5v2ooJwDdimS4GVn9HerCOgPwfshvQDNlMTxLcYju4v8BHMc5Rub9Q/ihvpQU74v2
ouZ9XIwA+C6pBLwvaqS8jE7HXOokgqJilaX/W/t+KEgiFry/txRTMU9WMD7tCN7lcfjCydmS3Lq+
3u6Hsr0S8BwNjcaDpZDnBTygUJd4JSqREnk33w==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
U46EWFmKmpZGaWfyL+dokyQtJtaOYsa7HCW/+fdtw9/yHKTWFpmqKBZngBj5rPkNhtTDDCJkqsYj
tUXg1j4tgIBaCQn9B0q/aG+B3gPLrudp9hLL25mVbsfiTzdekiV2hJMmhuMoavKKPJHC6zyW7kZi
80er82OQy8h+Df/fe6TRjH9xEt3/b80tRKUMbxkLfnnkAyyf1KfOhB6/uyI4mwXuQR+DsAbzybKR
YtXpOiW72tGrXTFlzcwbHamWZefqsilVpBw6V5dh33vYKGx50xwWpj76maAkpQrOpB7zufeldJe4
W1UOEN84AZdRTLkVSxamWo/wp8nP9fiGS/ItRw==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2021_07", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
qczgIJYpE/SzErzK7eWJBGcDFEzDLm8cKbwJbPXuM6YnJxx44W+E60R3war7K2QGFAkOoCDUtDC7
SghJGF32btaDLzeKm0tQ669sBtQmMIaBrlt7I9QBkNM8zN9GL92qxNC9o3UVWMOYy5BmH8nUPgcE
O6lRubeltlrTuDe7UJQ2nEPHcXjpUJJ8dxktyW+LovBy1OxW8g4GRAsmEJsoOEg0HuDdWcc4IshJ
PvwPJ7LblELAKsdkSt65y9VaklaEm7MlH4ImlgIa74TgRmutLUbWxM1QYhGE5rAzFhGU5i3RJOdx
L3N7GGGvLMW2z9NSHbIFX+/eNII9fNJ9nZbgLA==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Ti1NUgDv8YPk90APMwfu/mRr38QYwAxZfv0T6zQ89YS55t2EquEGVqrEafYX6rTydLOw8le1Oucv
f2oERpSSSTih/ScZneSZmuPE/Zh2BU1Ajv0j+/+0uEWXU+5lLPbDJjnapTmJXih1MYPf0SHpZZmE
BKj2IEBI9MPZlh6bxpa5BWJnyPdAvHf+UNaMXU9+pmbtrzUVebql4mFJu45Z3+ehmFY4FBW3zXMF
44C4TlHACLwL3vHVMCVfeKhgdVDbpE+/IFhTStz7mZ9h9RKGanQcs6YDVM1R+2RKA1QT1fX4FiQc
1V+FGmrm1ujxmFGXwpfNKByVlfCY0oWhRJCYYQ==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
HuEXFK0NXt09xU2yxxjng1OLsT+ZEM4EhqBgpr9D2ljw2vDaMBrqEsRQTc2B9soDq3ewDduHJXBd
OGYxkPnoN6LhjULtB2nTgjcH6NxA4puZ1ZNcndDndVBo8rTW5W1OqHq6InAG0CqPpTIkuqz3ECPl
EysI++MCDfH6tIzlekxJFIJ1McJsTq5rFuLzMMcrmkBxgcayDpOcCFuzZzCczxmt/cCCIKmDybwT
OQXmOcLJoYLP4sFu6R9c6xO8i6p++crv2N3eIxZHKbek9xBBZqQM9EYuEtsbkqAs9XZpa16i5njR
BDFxTKcP6r7JgFALJE89AZhBbate5JXWp0v4ECZD18aEL17CipwcWPutNMdG1apzSPP5y59n7rMG
yxBPz1gKHc3Emkl4WcO0hjICxqmO6dMXoY8JvBSf6ry2l0sH9Ihr3Bq5WWmlhPHnoaNr5jl//vNe
KfToWtn97eoVSt1LnmXXnSpdigbHr0UIg8AdkpdkuNRaWdVicDdgSo49

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
mokwst2bn6UxD6V9UdIgCIG1QQ/d0FiJqYGOTI2eHPV6YElaLjnJ8DnQmZnGS95o3x93FDOoa58C
RwYsX1fVoVtXkj1LuZq0k7q9vEe4T8xMjpkeYtIHY9k0Xhy1Lq/xRlfzGAf9fvf9e+f4r7aR/Sb/
uCZxxugG5niTwLENY1n3NthYL0jvo8Fmdw4Qg0nTCGWlVCws+09K0g9/lx6I9EcuHHemcHO3fOZG
lMc4NaPNozKwnyDMoWUkwiVxyFEPFaQLNYqzjvR+CqrWfhFLo96JWhL+eaDoNuZoBVYQtNH5ZwBL
BoO27Pw10lgcReGlZBz3BLO7T4ddynCx0+eSnw==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
PiP7AjOQqqouyQMoBQqgWIDhUSViq94rIvGiIJ/UKMDspM/yXw1caE8AhWHTjYckC4yLpPAz5P6s
1Z6flzDPrzVwg4e59X2cc4IMCHhedna0rDO804njcc6amRDTeLsMLTkWfvomB4xwszm2AgT+PRnB
WHd09ZUDVFjiBXT+Oa9AicgGJHrX3w823yBPuAa704kje/SzgtiDpcTU1eLmLhLW7LpEd9KIHd9s
ER7Uk9Orws0Kq9PMTqMX4hMn5K5mFakOeOURiEbUjdv5RiIJ2g/PlQXSItM8fHsBTQa6fOaJwQTI
vHwK3a8ZBHpfT1YH+n7wNiNUZwD4SFXm1QVx4g==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-PREC-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Ul5ZfTHJwMctaNhYRortUZizYMPYRef7uYqPSuMkxsArnxI/cjGh+KRMwzV86hyp/6TXSJIjm5ec
2wX2UONdPN+DOJ84jYC4JbgJQrPnTj7ioD8uLX/WlyPcQzyF5keqFgj5eR5s13FskVWCuAWf5m9w
mhFEKFjVXDAr7gVgAJh/hL8P6Psrnf+LGfiM8JhnDepsHEYykGlpD3fzru2BGgqHWqPqFMcnyVGl
vysaIXiJz/eYKvO8RGcgd3DJAM/wPm9A0m/DWcmSnczOgTjoqkHcBg2H5uJMLvufzmjImi6LYEqq
v04ESDEN31cSUzqUYcayvMFOnI/WNsWbFIa5+Q==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 29616)
`pragma protect data_block
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
`pragma protect end_protected
`ifndef GLBL
`define GLBL
`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;
    parameter GRES_WIDTH = 10000;
    parameter GRES_START = 10000;

//--------   STARTUP Globals --------------
    wire GSR;
    wire GTS;
    wire GWE;
    wire PRLD;
    wire GRESTORE;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;
    wire FCSBO_GLBL;
    wire [3:0] DO_GLBL;
    wire [3:0] DI_GLBL;
   
    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;
    reg GRESTORE_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;
    reg JTAG_RUNTEST_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (strong1, weak0) GSR = GSR_int;
    assign (strong1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;
    assign (strong1, weak0) GRESTORE = GRESTORE_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

    initial begin 
	GRESTORE_int = 1'b0;
	#(GRES_START);
	GRESTORE_int = 1'b1;
	#(GRES_WIDTH);
	GRESTORE_int = 1'b0;
    end

endmodule
`endif
