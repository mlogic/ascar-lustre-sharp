#!/usr/bin/python

# Merge qos_rules files.
# Usage: ./merge_qos_rules_files.py output qos_rules...

# Copyright (c) 2013, University of California, Santa Cruz, CA, USA.
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

from __future__ import print_function
import sys
import csv

debug = 0

output_file = sys.argv[1]
rules = []

first_rule_file = True
for i in range(2, len(sys.argv)):
    input_rule_file = sys.argv[i]
    if debug >= 1:
        print("Processing file", input_rule_file, file=sys.stderr)
    rule_no = 0
    row_id = 0
    # read in current rules, let's assume all rule files have the same number of lines
    with open(input_rule_file, 'rb') as csvfile:
        csvreader = csv.reader(csvfile)
        for row in csvreader:
            # first line is rule_no
            if rule_no == 0:
                rule_no = int(row[0])
                mrif_update_rate = int(row[1])
                continue

            # read in rules
            if first_rule_file:
                new_rule = dict(ack_ewma_lower = int(row[0]),
                                ack_ewma_upper = int(row[1]),
                                send_ewma_lower = int(row[2]),
                                send_ewma_upper = int(row[3]),
                                rtt_ratio100_lower = int(row[4]),
                                rtt_ratio100_upper = int(row[5]),
                                m100 = int(row[6]),
                                b100 = int(row[7]),
                                tau = int(row[8]),
                                used_times = int(row[9]),
                                ack_ewma_avg = int(row[10]),
                                send_ewma_avg = int(row[11]),
                                rtt_ratio100_avg = int(row[12]))
                rules.append(new_rule)
            else:
                if (rules[row_id]["ack_ewma_lower"] != int(row[0]) or
                    rules[row_id]["ack_ewma_upper"] != int(row[1]) or
                    rules[row_id]["send_ewma_lower"] != int(row[2]) or
                    rules[row_id]["send_ewma_upper"] != int(row[3]) or
                    rules[row_id]["rtt_ratio100_lower"] != int(row[4]) or
                    rules[row_id]["rtt_ratio100_upper"] != int(row[5]) or
                    rules[row_id]["m100"] != int(row[6]) or
                    rules[row_id]["b100"] != int(row[7]) or
                    rules[row_id]["tau"] != int(row[8])):
                    print("Rule file %s doesn't agree with previous rule files, maybe it's corrupted." % input_rule_file, file=sys.stderr)
                    exit(3)

                rules[row_id]["used_times"] += int(row[9])
                # calculate ack_ewma_avg and send_ewma_avg, see
                # https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Parallel_algorithm
                if rules[row_id]["used_times"] != 0:
                    nx = rules[row_id]["used_times"]

                    xa = rules[row_id]["ack_ewma_avg"]
                    xb = int(row[10])
                    nb = int(row[9])
                    delta = xb - xa
                    rules[row_id]["ack_ewma_avg"] = xa + delta * nb / nx

                    xa = rules[row_id]["send_ewma_avg"]
                    xb = int(row[11])
                    nb = int(row[9])
                    delta = xb - xa
                    rules[row_id]["send_ewma_avg"] = xa + delta * nb / nx

                    xa = rules[row_id]["rtt_ratio100_avg"]
                    xb = int(row[12])
                    nb = int(row[9])
                    delta = xb - xa
                    rules[row_id]["rtt_ratio100_avg"] = xa + delta * nb / nx
            row_id += 1

    first_rule_file = None

f = open(output_file, 'w')
print("%d,%d" % (rule_no, mrif_update_rate), file=f)
row_id = 0
for rule in rules:
    print('%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d' % (
                                    rule["ack_ewma_lower"], rule["ack_ewma_upper"],
                                    rule["send_ewma_lower"], rule["send_ewma_upper"],
                                    rule["rtt_ratio100_lower"], rule["rtt_ratio100_upper"],
                                    rule["m100"], rule["b100"], rule["tau"], rule["used_times"],
                                    rule["ack_ewma_avg"], rule["send_ewma_avg"],
                                    rule["rtt_ratio100_avg"]), file=f)
