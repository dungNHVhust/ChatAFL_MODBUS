#!/bin/bash

FUZZER=$1     #fuzzer name (e.g., aflnet) -- this name must match the name of the fuzzer folder inside the Docker container
OUTDIR=$2     #name of the output folder
OPTIONS=$3    #all configured options -- to make it flexible, we only fix some options (e.g., -i, -o, -N) in this script
TIMEOUT=$4    #time for fuzzing
SKIPCOUNT=$5  #used for calculating cov over time. e.g., SKIPCOUNT=5 means we run gcovr after every 5 test cases

strstr() {
  [ "${1#*$2*}" = "$1" ] && return 1
  return 0
}

#Commands for afl-based fuzzers (e.g., aflnet, aflnwe)
if $(strstr $FUZZER "afl") || $(strstr $FUZZER "llm"); then

  TARGET_DIR=${TARGET_DIR:-"modbus-tcp"}      #Diff 1
  INPUTS=${WORKDIR}/in-modbustcp

  # Run fuzzer-specific commands (if any)
  if [ -e ${WORKDIR}/run-${FUZZER} ]; then
    source ${WORKDIR}/run-${FUZZER}
  fi

  #Step-1. Do Fuzzing
  #Move to fuzzing folder
  cd $WORKDIR/${TARGET_DIR}/       #Diff 2
  timeout -k 2s --preserve-status $TIMEOUT /home/ubuntu/${FUZZER}/afl-fuzz -d -m none -i ${INPUTS} -x ${WORKDIR}/modbustcp.dict -o $OUTDIR -N tcp://127.0.0.1/1502 $OPTIONS -D 10000 -q 3 -s 3 -R -K ${WORKDIR}/libmodbus/test/unit-test-server 1502

  STATUS=$?

  #Step-2. Collect code coverage over time
  #Move to gcov folder
  cd $WORKDIR/modbustcp-gcov       #Diff 3

  #The last argument passed to cov_script should be 0 if the fuzzer is afl/nwe and it should be 1 if the fuzzer is based on aflnet
  #0: the test case is a concatenated message sequence -- there is no message boundary
  #1: the test case is a structured file keeping several request messages
  if [ $FUZZER == "aflnwe" ]; then
    cov_script ${WORKDIR}/${TARGET_DIR}/testProgs/${OUTDIR}/ 8554 ${SKIPCOUNT} ${WORKDIR}/${TARGET_DIR}/testProgs/${OUTDIR}/cov_over_time.csv 0
  else
    cov_script ${WORKDIR}/${TARGET_DIR}/testProgs/${OUTDIR}/ 8554 ${SKIPCOUNT} ${WORKDIR}/${TARGET_DIR}/testProgs/${OUTDIR}/cov_over_time.csv 1
  fi

  cd $WORKDIR/modbustcp-gcov      #Diff 5
  #copy .hh files since gcovr could not detect them
#   for f in BasicUsageEnvironment liveMedia groupsock UsageEnvironment; do
#     echo $f
#     cp $f/include/*.hh $f/
#   done
#   cd testProgs

  gcovr -r .. --html --html-details -o index.html
  mkdir ${WORKDIR}/${TARGET_DIR}/${OUTDIR}/cov_html/      #Diff 6
  cp *.html ${WORKDIR}/${OUTDIR}/cov_html/

  #Step-3. Save the result to the ${WORKDIR} folder
  #Tar all results to a file
  cd ${WORKDIR}/${TARGET_DIR}/testProgs     #Diff 7
  tar -zcvf ${WORKDIR}/${OUTDIR}.tar.gz ${OUTDIR}

  exit $STATUS
fi
