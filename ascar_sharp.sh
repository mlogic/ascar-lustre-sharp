#!/bin/bash
# SHARP main program
#
# Copyright (c) 2013, 2014, 2015, University of California,
# Santa Cruz, CA, USA.
#
# Developers:
#   Yan Li <yanli@cs.ucsc.edu>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the Storage Systems Research Center, the
#       University of California, nor the names of its contributors
#       may be used to endorse or promote products derived from this
#       software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# REGENTS OF THE UNIVERSITY OF CALIFORNIA BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
# OF THE POSSIBILITY OF SUCH DAMAGE.

set -e -u

cd `dirname $0`
. config

EXIT_SIGNAL_FILE=/tmp/STOP_ASCAR_SHARP

CLIENTS=80
ITER=8
BLOCK_SIZE=160m
DELAY=10
TRANSFER_SIZE=160m
SEARCH_METHOD=yan0
INITIAL_RULE=""
ENABLE_M=0
KEEP_FILES=0
DROP_CACHE=0
while getopts "b:cd:i:kmN:o:r:s:t:w:" OPT; do
    case $OPT in
        c)
            DROP_CACHE=1
            ;;
        b)
            BLOCK_SIZE=$OPTARG
            ;;
        d)
            DELAY=$OPTARG
            ;;
        i)
            ITER=$OPTARG
            ;;
        k)
            KEEP_FILES=1
            ;;
        m)
            ENABLE_M=1
            ;;
        N)
            CLIENTS=$OPTARG
            ;;
        o)
            SAVE_DIR=$OPTARG
            ;;
        r)
            INITIAL_RULE=$OPTARG
            ;;
        s)
            case $OPTARG in
                yan0mbt)
                    SEARCH_METHOD=yan0
                    ENABLE_M=1
                    ;;
                yan0bt)
                    SEARCH_METHOD=yan0
                    ENABLE_M=0
                    ;;
                remymbt)
                    SEARCH_METHOD=remy
                    ENABLE_M=1
                    ;;
                remybt)
                    SEARCH_METHOD=remy
                    ENABLE_M=0
                    ;;
                *)
                    echo "Unknown search method. Exiting..."
                    exit 2
            esac
            ;;
        t)
            TRANSFER_SIZE=$OPTARG
            ;;
        w)
            WORKLOAD=$OPTARG
            ;;
        *)
            echo "Wrong options"
            exit 2
            ;;
    esac
done

# system preparation
parallel -a $CLIENT_LIST_FILE ssh root@{} mount /share &>/dev/null || :
if [ $DROP_CACHE -eq 1 ]; then
    # disable ZFS cache
    parallel -a $SERVER_LIST_FILE ssh root@{} zfs set primarycache=metadata lustre1
    # disable ZFS file prefetch
    parallel -a $SERVER_LIST_FILE ssh root@{} echo 1 \> /sys/module/zfs/parameters/zfs_prefetch_disable
    # disable client readahead
    parallel -a $CLIENT_LIST_FILE ssh root@{} `pwd`/disable_client_cache.sh
fi

# test preparation
MAX_BW_FILE=${SAVE_DIR}/max_bandwidth
if [ -f $MAX_BW_FILE ]; then
    MAX_BW=`cat $MAX_BW_FILE`
else
    MAX_BW=0
fi
CANDIDATES_DIR=${SAVE_DIR}/candidate_rules
TESTED_RULES_DIR=${SAVE_DIR}/tested_rules
RESULTS_DIR=${SAVE_DIR}/results
WORKLOAD_BIN_DIR=${WORKLOAD%/*}
FAILURES=0

mkdir -p $CANDIDATES_DIR
mkdir -p $RESULTS_DIR
mkdir -p $TESTED_RULES_DIR

if [ -f "${SAVE_DIR}/epoch" ]; then
    EPOCH=`cat ${SAVE_DIR}/epoch`
else
    EPOCH=0
    echo $EPOCH >${SAVE_DIR}/epoch
    if [ -z "$INITIAL_RULE" ]; then
        echo "Starting Epoch 0 with default rule"
        if [ $ENABLE_M -eq 0 ]; then
            cat >${CANDIDATES_DIR}/0 <<EOF
1,2
0,2147483647,0,2147483647,0,2147483647,-1,0,20000
EOF
        else
            cat >${CANDIDATES_DIR}/0 <<EOF
1,2
0,2147483647,0,2147483647,0,2147483647,100,0,20000
EOF
        fi
    else
        echo "Starting Epoch 0 with rule" $INITIAL_RULE
        cp $INITIAL_RULE ${CANDIDATES_DIR}/0
    fi
fi
EPOCH_RESULT_DIR=${SAVE_DIR}/epoch_${EPOCH}
mkdir -p ${EPOCH_RESULT_DIR}

# Benchmark rule $2 and add/update the score line in round_summary_file $3
# Returns: VAR_PER,CANDIDATE_TRY in the variable specified by $1
#    VAR_PER: percentage of variance in mean (100*var/mean)
benchmark_rule() {
    local RET_VAR=$1
    local CANDIDATE=$2
    local ROUND_SUMMARY_FILE=$3
    # Gap between tests
    if [ $KEEP_FILES -eq 0 ]; then
        rm -f ${FSUT}/ior-test-file*
        rm -f ${FSUT}/btio.*.out
        rm -rf ${FSUT}/fbench*
    fi
    if [ $DROP_CACHE -eq 1 ]; then
        # drop server-side cache
        parallel -a $SERVER_LIST_FILE ssh root@{} echo 3 \> /proc/sys/vm/drop_caches
    fi
    parallel -a $CLIENT_LIST_FILE ssh root@{} umount ${FSUT}
    sleep 2
    parallel -a $CLIENT_LIST_FILE ssh root@{} mount  ${FSUT}
    if [ $DROP_CACHE -eq 1 ]; then
        # disable client readahead after each mount (not sure if this is needed, but do it anyway)
        parallel -a $CLIENT_LIST_FILE ssh root@{} `pwd`/disable_client_cache.sh
    fi
    sleep 3

    local RULE_TO_USE
    if [ -f "${CANDIDATES_DIR}/${CANDIDATE}" ]; then
        RULE_TO_USE="${CANDIDATES_DIR}/${CANDIDATE}"
    else
        RULE_TO_USE="${TESTED_RULES_DIR}/${CANDIDATE}/summary"
    fi
    ./deploy_rule_to_all_clients.sh "${RULE_TO_USE}"

    # SCORE_LINE format: ${RULE_NO},${SCORE},${CANDIDATE_AVG_BW},${CANDIDATE_AVG_VAR},${CANDIDATE_TRIED_TIMES}
    local OLD_SCORE_LINE=`grep "^${CANDIDATE}," $ROUND_SUMMARY_FILE`
    if [ x$OLD_SCORE_LINE = x ]; then
        local CANDIDATE_AVG_BW=0
        local CANDIDATE_AVG_VAR=0
        local CANDIDATE_TRY=0
    else
        local CANDIDATE_AVG_BW=`echo $OLD_SCORE_LINE | cut -d, -f 3`
        local CANDIDATE_AVG_VAR=`echo $OLD_SCORE_LINE | cut -d, -f 4`
        local CANDIDATE_TRY=`echo $OLD_SCORE_LINE | cut -d, -f 5`
    fi
    CANDIDATE_TRY=$(( $CANDIDATE_TRY + 1 ))

    if [ $CANDIDATE_TRY -eq 1 ]; then
        local OUTPUT_DIR="${RESULTS_DIR}/${CANDIDATE}"
        if [ -d "$OUTPUT_DIR" ]; then
            # delete old results (they are mostly half finished anyway)
            rm -rf "$OUTPUT_DIR"
        fi
    else
        local OUTPUT_DIR="${RESULTS_DIR}/${CANDIDATE}/${CANDIDATE_TRY}"
    fi
    mkdir -p "$OUTPUT_DIR"

    1>&2 echo "Benchmarking rule $CANDIDATE start"
    local TEST_OUT_FILE=${OUTPUT_DIR}/test.out
    if ! $WORKLOAD -o "${OUTPUT_DIR}" &>"$TEST_OUT_FILE"; then
        RC=$?
        1>&2 echo "Benchmarking rule $CANDIDATE failed with error code $RC"
        FAILURES=$(( $FAILURES + 1 ))
        return 2
    else
        1>&2 echo "Benchmarking rule $CANDIDATE succeeded"
    fi
    # Get the qos_rules from the all clients, which contains
    # used_times and {ack,send}_ewma_avg
    mkdir -p "${TESTED_RULES_DIR}/${CANDIDATE}"
    # We only gather the first try's QoS trigger data
    if [ $CANDIDATE_TRY -eq 1 ]; then
        parallel -a "$CLIENT_LIST_FILE" ./gather_qos_rules.sh {} "${TESTED_RULES_DIR}/${CANDIDATE}"
        ./merge_qos_rules_files.py "${TESTED_RULES_DIR}/${CANDIDATE}/summary" ${TESTED_RULES_DIR}/${CANDIDATE}/*.qos_rules
    fi

    # get merit score
    # Rounded bandwidth
    local BANDWIDTH=`${WORKLOAD_BIN_DIR}/extract_bandwidth.sh $OUTPUT_DIR`
    if [ x$BANDWIDTH = x -o $BANDWIDTH -eq 0 ]; then
        1>&2 echo "Cannot get bandwidth, error"
        FAILURES=$(( $FAILURES + 1 ))
        return
    else
        CANDIDATE_AVG_BW=`echo "( $CANDIDATE_AVG_BW * ( $CANDIDATE_TRY - 1 ) + $BANDWIDTH ) / $CANDIDATE_TRY" | bc`
        if [ $CANDIDATE_AVG_BW -gt $MAX_BW ]; then
            MAX_BW=$CANDIDATE_AVG_BW
            echo $MAX_BW >$MAX_BW_FILE
        fi
    fi
    if [ -x ${WORKLOAD_BIN_DIR}/extract_stddev_over_time.sh ]; then
        local VAR=`${WORKLOAD_BIN_DIR}/extract_stddev_over_time.sh $OUTPUT_DIR`
        if [ x$VAR = x ]; then
            VAR=0
        fi
    else
        local VAR=0
    fi
    CANDIDATE_AVG_VAR=`echo "( $CANDIDATE_AVG_VAR * ( $CANDIDATE_TRY - 1 ) + $VAR ) / $CANDIDATE_TRY" | bc`
    SCORE=`${WORKLOAD_BIN_DIR}/calc_score.py $CANDIDATE_AVG_BW $CANDIDATE_AVG_VAR`
    SCORE_LINE=${CANDIDATE},${SCORE},${CANDIDATE_AVG_BW},${CANDIDATE_AVG_VAR},${CANDIDATE_TRY}

    # update ROUND_SUMMARY_FILE
    if grep -q "^${CANDIDATE}," $ROUND_SUMMARY_FILE; then
        sed -i "s/^${CANDIDATE},.*/${SCORE_LINE}/g" $ROUND_SUMMARY_FILE
    else
        echo "$SCORE_LINE" >>$ROUND_SUMMARY_FILE
    fi

    local VAR_PER=`echo "100 * $CANDIDATE_AVG_VAR / $CANDIDATE_AVG_BW" | bc`
    eval "$RET_VAR='${VAR_PER},${CANDIDATE_TRY}'"
}

# test all rules in ${CANDIDATES_DIR} and store results in
# $RESULTS_DIR and $ROUND_SUMMARY_FILE
# (all debug output must go to stderr)
# returns best score line in $1
get_best_round_score() {
    local RET_VAR=$1
    local ROUND_SUMMARY_FILE=$2
    while true; do   # round loop
        # Shall we exit?
        if [ -f "$EXIT_SIGNAL_FILE" ]; then
            1>&2 echo "Exit signal file detected. Exiting..."
            exit 6
        fi

        local CANDIDATES_COUNT=`ls $CANDIDATES_DIR | wc -l`
        if [ $CANDIDATES_COUNT -eq 0 ]; then
            break
        fi
        local CANDIDATE=`ls $CANDIDATES_DIR | head -1`
        while true; do # candidate loop
            # benchmark_rule() puts ${VAR_PER},${CANDIDATE_TRY} into $1
            local S
            if ! benchmark_rule S $CANDIDATE $ROUND_SUMMARY_FILE; then
                if [ $FAILURES -gt 10 ]; then
                    1>&2 echo "Too many failures, aborting..."
                    exit 7
                fi
                continue
            fi
            local VAR_PER=`echo $S | cut -d, -f 1`
            local CANDIDATE_TRY=`echo $S | cut -d, -f 2`

            if [ $VAR_PER -le $VAR_PER_THRESHOLD ]; then
                1>&2 echo "VAR_PER is $VAR_PER, stable enough, proceeding to next rule"
                break
            elif [ $CANDIDATE_TRY -ge 3 ]; then
                1>&2 echo "CANDIDATE_TRY is $CANDIDATE_TRY, VAR_PER is $VAR_PER, giving up trying this rule, proceeding to next rule"
                break
            fi
            1>&2 echo "VAR_PER is $VAR_PER, too high, trying this rule one more time"
        done
        # we do nothing if the score line is missing from
        # ANALYSIS_FILE; that may be from a bad run
        rm "${CANDIDATES_DIR}/${CANDIDATE}"
    done

    # Re-run the top score rule if it's tried less than 3 times
    while true; do
        # get the round's best score line
        local SCORE_LINE=`${WORKLOAD_BIN_DIR}/get_highest_score.sh $ROUND_SUMMARY_FILE $MAX_BW`
        local NO_SCORE=`wc -l $ROUND_SUMMARY_FILE | awk '{print $1}'`
        local CANDIDATE=`echo $SCORE_LINE | cut -d, -f 1`
        local CANDIDATE_AVG_BW=`echo $SCORE_LINE | cut -d, -f 3`
        local CANDIDATE_AVG_VAR=`echo $SCORE_LINE | cut -d, -f 4`
        local CANDIDATE_TRY=`echo $SCORE_LINE | cut -d, -f 5`
        if [ $CANDIDATE_TRY -ge 3 -o $NO_SCORE -eq 1 ]; then
            eval "$RET_VAR=$SCORE_LINE"
            return
        fi

        1>&2 echo "Re-exam best round candidate $CANDIDATE"
        local S
        if ! benchmark_rule S $CANDIDATE $ROUND_SUMMARY_FILE; then
            if [ $FAILURES -gt 10 ]; then
                1>&2 echo "Too many failures, aborting..."
                exit 7
            fi
        fi
    done
}


# rm exit signal file at start
rm -f "$EXIT_SIGNAL_FILE"

while true; do       # main work loop
    EPOCH=`cat ${SAVE_DIR}/epoch`
    EPOCH_RESULT_DIR=${SAVE_DIR}/epoch_${EPOCH}
    mkdir -p ${EPOCH_RESULT_DIR}
    if [ -f ${EPOCH_RESULT_DIR}/round ]; then
        ROUND=`cat ${EPOCH_RESULT_DIR}/round`
    else
        ROUND=0
        echo $ROUND >${EPOCH_RESULT_DIR}/round
    fi

    # run all candidates in this round and find the best round score
    ROUND_SUMMARY_FILE=${EPOCH_RESULT_DIR}/round_${ROUND}_summary.csv

    echo "Running Epoch $EPOCH Round $ROUND"
    get_best_round_score ROUND_BEST_SCORE_LINE $ROUND_SUMMARY_FILE

    search_method/${SEARCH_METHOD}/next_round.sh "${SAVE_DIR}" "${ROUND_BEST_SCORE_LINE}"
done # epoch loop
