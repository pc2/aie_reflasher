# An attempt at an AI Engine reflasher for the VCK5000

This (currently failed) project was an attempt to reconfigure the AI engine array, (and only the AI engine array) from within the device itself. 

Our approach was to make a hardware core, with two interfaces. A AXI4-Full "bulk" interface that reads commands from DDR and is responsible for DMA to the AIE array, and an AXI4-Lite "small" interface that handles individual register read and writes. 

The DDR is mapped to 0x100_0000_0000 in Tapasco, and the AI engine array is mapped to address 0x200_0000_0000. We discovered that the cdo files (found in tests/AIEngineReflasher/adf_a, and adf_b) write to this address range. 

Now, an issue we ran into was that a vanishing few of these commands write to an address range 0xf70a0000. These appear to be registers only visible to the CIPS. 

like:
```
write64 0xf70a000c 0xf9e8d7c6
mask_poll64 0xf70a000c 0x0 0x0 0x1
write64 0xf70a0200 0x1
mask_poll64 0xf70a0200 0x0 0x0 0x1
write64 0xf70a000c 0x0
mask_poll64 0xf70a000c 0x0 0x0 0x1
mask_write64 0x20000036040 0x1 0x0
mask_write64 0x20000836040 0x1 0x0
mask_write64 0x20001036040 0x1 0x0
mask_write64 0x20001836040 0x1 0x0
```

Perhaps a future CIPS implementation will make it possible to do AI engine reconfiguration. 

## To reproduce
Place the plugin [tapasco/aie_reconfig.tcl](tapasco/aie_reconfig.tcl) in the plugins directory of your tapasco build. 
Copy this plugin file to `$TAPASCO_HOME_TOOLFLOW/vivado/platform/vck5000/plugins/`. 

First create the Vector-Norm IP core from [tapasco-examples/Vector-Norm](tapasco-examples/Vector-Norm). Once it's been built and is therefore registered in your tapasco workspace, and the plugin is present, you can build the full bitstream with `tapasco --jobsFile tapasco/vector-norm_a.json` and `tapasco --jobsFile tapasco/vector-norm_b.json`. These will be two builds with identical interface, just differing AI Engine implementation. 

For convenience, the two compiled [libadf_a.a](libadf_a.a) and [libadf_b.a](libadf_b.a) are provided in this repo too. 
They were compiled with fixed interface points defined in [tapasco-examples/Vector-Norm/aie/src/graph.h](tapasco-examples/Vector-Norm/aie/src/graph.h), insert at line 22:

```cpp
		location<PLIO>(in_x) = shim(6 + 6, 2 * 0);
		location<PLIO>(in_y) = shim(6 + 7, 2 * 0);
		location<PLIO>(out_z) = shim(6 + 8, 2 * 0);
```

This binds the input interfaces to shim tiles 12 and 13, and the output interface to shim tile 14. 

The [libadf_b.a](libadf_b.a) variant was changed to add a multiply by 2.0 after the vector norm, to distinguish them. ([tapasco-examples/Vector-Norm/aie/src/sum_sqrt.cpp](tapasco-examples/Vector-Norm/aie/src/sum_sqrt.cpp) line 14):

```cpp
        *outIt++ = aie::mul(aie::sqrt(aie::add(inX_i, inY_i)), aie::broadcast<float, VECTOR_SIZE>(2.0f));
```
