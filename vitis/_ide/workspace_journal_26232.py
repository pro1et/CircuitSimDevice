# 2026-07-26T08:45:43.208815600
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="fir_design")
comp.build()

