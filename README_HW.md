## Quantize model
To prepare the model for hardware implementation, data quantization is needed because the hardware design is wrtten to use quantized operations. The purpose of this step is to generate a file of quantized weights from the trained weights from the training step. This quantized weights file is later converted into a binary file for hardware implementation.

A quantized weights file is already included in the repo with the path './weights/quantized_weights_pertensor_symmetric.pth'. To re-quantize the model, run the 'quantization_convert.py' script with the following arguments:
- **--checkpoint_path**: path to the trained checkpoint directory.
- **--dataset_path**: path to dataset directory, used to calibrate the quantized model.
- **--quantized_weights_path**: path to the **OUTPUT** quantized weights file, with the extension .pth.

Model quantization can be run using this example command:

    python3 ./quantization_convert.py                                                   \
        --dataset_path             ./dataset                                            \
        --checkpoint_path          ./checkpoint                                         \
        --quantized_weights_path   ./weights/quantized_weights_pertensor_symmetric.pth  

## Preparations for hardware implementation
To prepare for running the FPGA, several files need to be generated. These include:
- RTL code for the CNN model (verilog).
- Binary weights file, generated from the quantized weights file.
- Constraints for Vivado if ILA debug core is wanted (.xdc)

All of these files are already included in the repo, but if they need to be re-generated for some reason, modification or otherwise, this can be done by using the '*_gen.py' scripts.
- To generate RTL code for the model, run the './fpga_model_rtl_gen.py' script. The RTLs for the component modules are already defined the './vivado_sources/rtl', with the 'model.v' file calling multiple 'conv' instances with different parameter configurations based on the quantized model. Should the quantized model be modified somehow and a new 'model.v' need to be generated accordingly, the './fpga_model_rtl_gen.py' script can be run. This will overwrite the old file. To write to a different file, a path can be passed to the --rtl_path argument.

        python3 ./fpga_model_rtl_gen.py

- To generate binary weights file for the FPGA, the quantized weights file must first exist ('./quantization_convert.py'). The './fpga_weights_gen.py' script can be run with the following arguments:
    - **--weights_bin_path**: path to the output binary weights file.
    - **--quantized_weights_path**: path to the quantized weights file.

    For example:

        python3 ./fpga_weights_gen.py                                                       \
            --weights_bin_path         ./weights/fpga_weights.bin                           \
            --quantized_weights_path   ./weights/quantized_weights_pertensor_symmetric.pth  

- Finally, hardware can be synthesized with an Integrated Logic Analyzer (ILA) core that samples signals during runtime and send to Vivado to render waveform for debugging or just to observe the operations of the circuit underneath. To include this ILA core without using GUI (since the synthesized design is quite large and hard to navigate in GUI), a constraint file (.xdc) needs to be included before running Synthesis. This file is included in the repo at the path './vivado_sources/constraints/debug.xdc' that mark all the signals that I think is important. If you want to modify the signals included, they can be modified in the './fpga_debug_constrs_gen.py' script by changing the 'debug_ports' list.

    However, selecting a random net from the RTL design is not guaranteed to work as the synthesized netlist can be modified when Vivado tries to optimize the design. Selecting nets for debugging will require some experimentation to figure out. The ones I have included are tested in Vivado v2020.2.2.

    The script can be run without any arguments, and will overwrite the old .xdc file. To write to a different file, a path can be passed to the '--debug_path' argument

        python3 ./fpga_debug_constrs_gen.py

## Installing drivers for XMDA
README_XDMA.md

## Building Vivado project and run implementation

## Test model