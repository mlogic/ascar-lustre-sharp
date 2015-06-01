#!/bin/bash
# Generate candidate rule sets for next round using search method YAN0
#
# Copyright (c) 2015, University of California, Santa Cruz, CA, USA.
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

if [ -f ${SAVE_DIR}/next_rule_sn ]; then
    NEXT_RULE_SN=`cat ${SAVE_DIR}/next_rule_sn`
else
    NEXT_RULE_SN=1
    echo $NEXT_RULE_SN >${SAVE_DIR}/next_rule_sn
fi

EPOCH_BEST_SCORE_FILE=${SAVE_DIR}/epoch_${EPOCH}_best_score.csv
if [ ! -f $EPOCH_BEST_SCORE_FILE ]; then
    EPOCH_BEST_SCORE_LINE="0,0"
else
    EPOCH_BEST_SCORE_LINE=`cat $EPOCH_BEST_SCORE_FILE`
fi
EPOCH_BEST_SCORE=`get_score $EPOCH_BEST_SCORE_LINE`

# is this round's best score better than current epoch best score?
# $ROUND_BEST_SCORE_LINE = $EPOCH_BEST_SCORE_LINE is possible if
# the processing of the last round results was interrupted before
# it can finish
if [ $ROUND_BEST_SCORE -gt $EPOCH_BEST_SCORE -o $ROUND_BEST_SCORE_LINE = $EPOCH_BEST_SCORE_LINE ]; then
    EPOCH_BEST_SCORE_LINE=$ROUND_BEST_SCORE_LINE
    echo $EPOCH_BEST_SCORE_LINE >$EPOCH_BEST_SCORE_FILE
    EPOCH_BEST_RULE=`get_rule $EPOCH_BEST_SCORE_LINE`
    NEXT_RULE_SN=`${SCRIPT_HOME}/../remy/gen_candidate_rules.py "${TESTED_RULES_DIR}/${EPOCH_BEST_RULE}/summary" "${CANDIDATES_DIR}" $NEXT_RULE_SN | cut -f 1 -d','`
    echo $NEXT_RULE_SN >${SAVE_DIR}/next_rule_sn
    ROUND=$(( $ROUND + 1 ))
    echo $ROUND >${EPOCH_RESULT_DIR}/round
else
    EPOCH_BEST_RULE=`get_rule $EPOCH_BEST_SCORE_LINE`
    NEXT_RULE_SN=`${SCRIPT_HOME}/../remy/split_rule.py "${TESTED_RULES_DIR}/${EPOCH_BEST_RULE}/summary" "${CANDIDATES_DIR}" $NEXT_RULE_SN`
    echo $NEXT_RULE_SN >${SAVE_DIR}/next_rule_sn
    # start a new epoch
    EPOCH=$(( $EPOCH + 1 ))
    echo $EPOCH >${SAVE_DIR}/epoch
    EPOCH_RESULT_DIR=${SAVE_DIR}/epoch_${EPOCH}
    mkdir -p ${EPOCH_RESULT_DIR}
    ROUND=0
    echo $ROUND >${EPOCH_RESULT_DIR}/round
fi
