#!/bin/bash
# SHARP Test Cases
#
# Copyright (c) 2015, University of California, Santa Cruz, CA, USA.
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

test_search_method_yan0()
{
    local SM=yan0
    local TEST_DIR=`mktemp -d -u /tmp/test_sharp.XXXXXX`
    cp -a test_search_method "$TEST_DIR"
    ../search_method/${SM}/next_round.sh "$TEST_DIR" 10,275000,275,27,3
    diff -Nur "$TEST_DIR" exp_${SM}
    echo Test ${SM} PASS
}

test_search_method_remy()
{
    local SM=remy
    local TEST_DIR=`mktemp -d -u /tmp/test_sharp.XXXXXX`
    cp -a test_search_method "$TEST_DIR"

    # round 1
    ../search_method/${SM}/next_round.sh "$TEST_DIR" 10,275000,275,27,3
    diff -Nur "$TEST_DIR" exp_remy_0
    
    # round 2, rule 6 is still being improved
    cp -r "$TEST_DIR/tested_rules/"{10,470}
    rm "$TEST_DIR/candidate_rules/"*
    ../search_method/${SM}/next_round.sh "$TEST_DIR" 470,276000,276,27,3
    diff -Nur "$TEST_DIR" exp_remy_1

    # round 3, rule 6 can't be improved any more
    cp -r "$TEST_DIR/tested_rules/"{10,777}
    rm "$TEST_DIR/candidate_rules/"*
    ../search_method/${SM}/next_round.sh "$TEST_DIR" 777,271000,271,27,3
    diff -Nur "$TEST_DIR" exp_remy_2

    # round 4
    cp -r "$TEST_DIR/tested_rules/"{10,1469}
    rm "$TEST_DIR/candidate_rules/"*
    ../search_method/${SM}/next_round.sh "$TEST_DIR" 1469,271000,271,27,3
    diff -Nur "$TEST_DIR" exp_remy_3

    # round 5, no need to check the results of the following rounds
    # because they simply finish one rule a time
    cp -r "$TEST_DIR/tested_rules/"{10,2010}
    rm "$TEST_DIR/candidate_rules/"*
    ../search_method/${SM}/next_round.sh "$TEST_DIR" 2010,271000,271,27,3

    # round 6
    cp -r "$TEST_DIR/tested_rules/"{10,2510}
    rm "$TEST_DIR/candidate_rules/"*
    ../search_method/${SM}/next_round.sh "$TEST_DIR" 2510,271000,271,27,3

    # round 7
    cp -r "$TEST_DIR/tested_rules/"{10,3010}
    rm "$TEST_DIR/candidate_rules/"*
    ../search_method/${SM}/next_round.sh "$TEST_DIR" 3010,271000,271,27,3

    # round 8
    cp -r "$TEST_DIR/tested_rules/"{10,3510}
    rm "$TEST_DIR/candidate_rules/"*
    ../search_method/${SM}/next_round.sh "$TEST_DIR" 3510,271000,271,27,3

    # round 9
    cp -r "$TEST_DIR/tested_rules/"{10,4010}
    rm "$TEST_DIR/candidate_rules/"*
    ../search_method/${SM}/next_round.sh "$TEST_DIR" 4010,271000,271,27,3
    diff -Nur "$TEST_DIR" exp_remy_4

    # round 10
    cp -r "$TEST_DIR/tested_rules/"{10,4510}
    rm "$TEST_DIR/candidate_rules/"*
    ../search_method/${SM}/next_round.sh "$TEST_DIR" 4510,271000,271,27,3
    diff -Nur "$TEST_DIR" exp_remy_5

    echo Test ${SM} PASS
}

test_search_method_remy_split_rule()
{
    local SM=remy
    local TEST_DIR=`mktemp -d -u /tmp/test_sharp.XXXXXX`
    cp -a test_remy_split_rule "$TEST_DIR"

    ../search_method/${SM}/next_round.sh "$TEST_DIR" 4510,271000,271,27,3
    diff -Nur "$TEST_DIR" exp_remy_split_rule

    echo Test ${SM} split rule PASS
}


test_search_method_yan0
test_search_method_remy
test_search_method_remy_split_rule
