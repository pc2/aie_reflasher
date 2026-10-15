
# build TaPaSCo bitstream
echo "Generating device image"
sed -i "s,PATH_TO_THIS_REPO,$PWD,g" vector-norm.json
tapasco import hw/DataStreamerVN/build/ip/DataStreamerVN.zip as 8847 -p vck5000
tapasco --jobsFile vector-norm.json

if [ -f $TAPASCO_WORK_DIR/compose/axi4mm/vck5000/DataStreamerVN/001/312.5+AI-Engine+DMA-Streaming/axi4mm-vck5000--DataStreamerVN_1--313.pdi ]; then
	echo "Device image created successfully"
	echo "PDI file: $TAPASCO_WORK_DIR/compose/axi4mm/vck5000/DataStreamerVN/001/312.5+AI-Engine+DMA-Streaming/axi4mm-vck5000--DataStreamerVN_1--313.pdi"
else
	echo "ERROR: Failed to create device image"
fi
