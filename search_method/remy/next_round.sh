#!/bin/bash
# Generate candidate rule sets for next round using search method Remy as
# described in paper ``TCP ex Machina: Computer-Generated Congestion Control''
# by Keith Winstein and Hari Balakrishnan
#
# Copyright (c) 2015 University of California, Santa Cruz, CA, USA.
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

SAVE_DIR=$1
ROUND_BEST_SCORE_LINE=$2
SCRIPT_HOME=`dirname $0`
CANDIDATES_DIR=${SAVE_DIR}/candidate_rules
TESTED_RULES_DIR=${SAVE_DIR}/tested_rules

# get rule name from a score line, a score line is
# RULE_NAME,SCORE
get_rule() {
    local SCORE_LINE=$1
    echo "$SCORE_LINE" | cut -f 1 -d','
}

# get score from a score line
get_score() {
    local SCORE_LINE=$1
    echo "$SCORE_LINE" | cut -f 2 -d','
}

EPOCH=`cat ${SAVE_DIR}/epoch`
ROUND=`cat ${SAVE_DIR}/epoch_${EPOCH}/round`
ROUND_BEST_SCORE=`get_score $ROUND_BEST_SCORE_LINE`
EPOCH_RESULT_DIR=${SAVE_DIR}/epoch_${EPOCH}
EPOCH_FINISHED_RULES_FILE=${SAVE_DIR}/epoch_${EPOCH}/finished_rules

if [ -f ${SAVE_DIR}/next_rule_sn ]; then
    NEXT_RULE_SN=`cat ${SAVE_DIR}/next_rule_sn`
else
    NEXT_RULE_SN=1
    echo $NEXT_RULE_SN >${SAVE_DIR}/next_rule_sn
fi

# the current rule we are optimizing
CURRENT_RULE=-1
RULE_BEST_SCORE_LINE="0,0"
if [ -f "${SAVE_DIR}/epoch_${EPOCH}/current_rule" ]; then
    CURRENT_RULE=`cat "${SAVE_DIR}/epoch_${EPOCH}/current_rule"`
    RULE_BEST_SCORE_FILE=${SAVE_DIR}/epoch_${EPOCH}/rule_${CURRENT_RULE}_best_score.csv
    if [ -f $RULE_BEST_SCORE_FILE ]; then
        RULE_BEST_SCORE_LINE=`cat $RULE_BEST_SCORE_FILE`
    fi
fi
RULE_BEST_SCORE=`get_score $RULE_BEST_SCORE_LINE`

# is this round's best score better than current rule's best score?
# $ROUND_BEST_SCORE_LINE = $RULE_BEST_SCORE_LINE is possible if
# the processing of the last round results was interrupted before
# it can finish
if [ $ROUND_BEST_SCORE -gt $RULE_BEST_SCORE -o $ROUND_BEST_SCORE_LINE = $RULE_BEST_SCORE_LINE ]; then
    RULE_BEST_SCORE_LINE=$ROUND_BEST_SCORE_LINE
    BEST_RULE=`get_rule $ROUND_BEST_SCORE_LINE`
    ROUND=$(( $ROUND + 1 ))
else
    # CURRENT_RULE is assigned above
    echo $CURRENT_RULE >>"$EPOCH_FINISHED_RULES_FILE"

    BEST_RULE=`get_rule $RULE_BEST_SCORE_LINE`

    COUNT_RULES_FINISHED=`wc -l "$EPOCH_FINISHED_RULES_FILE" | awk '{print $1}'`
    COUNT_ALL_RULES=`wc -l "${TESTED_RULES_DIR}/${BEST_RULE}/summary" | awk '{print $1}'`
    COUNT_ALL_RULES=`expr $COUNT_ALL_RULES - 1`
    if [ $COUNT_RULES_FINISHED -eq $COUNT_ALL_RULES ]; then
        # proceed to next epoch
        EPOCH=$(( $EPOCH + 1 ))
        echo $EPOCH >${SAVE_DIR}/epoch
        EPOCH_RESULT_DIR=${SAVE_DIR}/epoch_${EPOCH}
        EPOCH_FINISHED_RULES_FILE=${SAVE_DIR}/epoch_${EPOCH}/finished_rules
        mkdir -p ${EPOCH_RESULT_DIR}
        ROUND=0
        CURRENT_RULE=-1

        if [ $(($EPOCH % 4)) -eq 0 -o $COUNT_ALL_RULES -eq 1 ]; then
            NEXT_RULE_SN=`${SCRIPT_HOME}/split_rule.py "${TESTED_RULES_DIR}/${BEST_RULE}/summary" "${CANDIDATES_DIR}" $NEXT_RULE_SN`
            echo $NEXT_RULE_SN >${SAVE_DIR}/next_rule_sn
            exit 0
        fi
    else
        # proceed to next rule
        CURRENT_RULE=-1
        ROUND=$(( $ROUND + 1 ))
    fi
fi
GEN_CANDIDATE_OUTPUT=`${SCRIPT_HOME}/gen_candidate_rules.py "${TESTED_RULES_DIR}/${BEST_RULE}/summary" "${CANDIDATES_DIR}" $NEXT_RULE_SN $CURRENT_RULE "$EPOCH_FINISHED_RULES_FILE"`
NEXT_RULE_SN=`echo $GEN_CANDIDATE_OUTPUT | cut -f 1 -d','`
CURRENT_RULE=`echo $GEN_CANDIDATE_OUTPUT | cut -f 2 -d','`
RULE_BEST_SCORE_FILE=${SAVE_DIR}/epoch_${EPOCH}/rule_${CURRENT_RULE}_best_score.csv
echo $RULE_BEST_SCORE_LINE >$RULE_BEST_SCORE_FILE
echo $NEXT_RULE_SN >${SAVE_DIR}/next_rule_sn
echo $ROUND >${EPOCH_RESULT_DIR}/round
echo $CURRENT_RULE >"${SAVE_DIR}/epoch_${EPOCH}/current_rule"
