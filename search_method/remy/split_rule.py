#!/usr/bin/python
# Slice a rule cube into smallers cubes at split points.
#
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
__author__ = 'yanli'
import sys
import csv

# consts
debug = 0
dimension = 3
used_times_col_id = 9
# columns that have an equal or higher ID than this are ignored in output file
output_col_range = 9
split_point_start_col = 10
split_point_end_col = 13

def splice_cube(rule, split_points):
    global dimension
    ret = []
    ret.append(rule)
    for dim in range(dimension):
        new_rules = []
        for rule in ret:
            # split rule along the dim-th dimension
            new_rule1 = []
            new_rule2 = []
            for i in range(dimension):
                if i != dim:
                    new_rule1.append(rule[i * 2])
                    new_rule1.append(rule[i * 2 + 1])
                    new_rule2.append(rule[i * 2])
                    new_rule2.append(rule[i * 2 + 1])
                else:
                    split_point = split_points[dim]
                    lower_limit = rule[i * 2]
                    upper_limit = rule[i * 2 + 1]
                    if not (lower_limit < split_point and split_point < upper_limit):
                        split_point = lower_limit + (upper_limit - lower_limit) / 2
                    new_rule1.append(lower_limit)
                    new_rule1.append(split_point)
                    new_rule2.append(split_point)
                    new_rule2.append(upper_limit)
            # duplicate all rest fields in rule
            for col in rule[dimension * 2:]:
                new_rule1.append(col)
                new_rule2.append(col)
            new_rules.append(new_rule1)
            new_rules.append(new_rule2)
        ret = new_rules
    return ret

def write_rule(file, rule):
    s = ""
    for col_id in range(output_col_range):
        if s != "":
            s += ","
        s += str(rule[col_id])
    print >>file, s

m100_upper_limit = 20*100
m100_lower_limit = 0
b100_upper_limit = 20*100
b100_lower_limit = -b100_upper_limit

rule_no = 0
rules = []
busiest_rule_used_times = 0
row_id = 0

input_rule_file = sys.argv[1]
output_dir      = sys.argv[2]
next_rule_sn    = int(sys.argv[3])

# read in current rules
with open(input_rule_file, 'rb') as csvfile:
    csvreader = csv.reader(csvfile)
    for row in csvreader:
        # first line is rule_no
        if rule_no == 0:
            rule_no = int(row[0])
            mrif_update_rate = int(row[1])
            continue

        # read in rules
        new_rule = []
        for col in row:
            new_rule.append(int(col))
        rules.append(new_rule)
        if new_rule[used_times_col_id] > busiest_rule_used_times:
            busiest_rule_used_times = new_rule[used_times_col_id]
            busiest_rule = new_rule
            busiest_rule_id = row_id

        row_id += 1

if debug > 0:
    print('Busiest rule ID: %d' % busiest_rule_id)

filename = output_dir + '/' + str(next_rule_sn)
next_rule_sn += 1
if debug > 0:
    print 'Writing rule file', filename
f = open(filename, 'w')

print >>f, "%d,%d" % (rule_no + pow(2, dimension) - 1, mrif_update_rate)
row_id = 0
for rule in rules:
    if row_id != busiest_rule_id:
        write_rule(f, rule)
    else:
        split_points = rule[split_point_start_col:split_point_end_col]
        new_rules = splice_cube(rule, split_points)
        for nr in new_rules:
            write_rule(f, nr)
    row_id += 1

print next_rule_sn
