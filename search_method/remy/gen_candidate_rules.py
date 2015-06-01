#!/usr/bin/python
# Generate candidate rules in search space.
#
# Copyright (c) 2013, 2014, 2015, University of California, Santa Cruz, CA, USA.
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
import os.path

# consts
debug = 0
used_times_col_id = 9

if len(sys.argv) < 4:
    print("Usage:", sys.argv[0], "input_rule_file output_dir next_rule_sn [working_on_rule] [list_file_of_excluded_rules]")
    exit(2)

input_rule_file = sys.argv[1]
output_dir      = sys.argv[2]
next_rule_sn    = int(sys.argv[3])
working_on_rule = -1
excluded_rules = []
if len(sys.argv) >= 5:
    working_on_rule = int(sys.argv[4])
    list_file_of_excluded_rules = sys.argv[5]
    if os.path.isfile(list_file_of_excluded_rules):
        f = open(list_file_of_excluded_rules, 'r')
        while True:
            s = f.readline()
            if s == '':
                break
            excluded_rules.append(int(s))
    if debug > 0:
        print('excluded_rules: ', excluded_rules)

# Load excluded rules from file. Excluded rules will be ignored.
# They are used by the Remy method.

fields = []
# Remy used 20 for upper limit for b with a max_window = 256.
# Our mrif_upper_limit is 30, therefore we should use
# mrif_upper_limit / ( 256 / 20 ) * 100
mrif_upper_limit = 30
b100_upper_limit = mrif_upper_limit * 20 * 100 / 256
b100_lower_limit = -b100_upper_limit
fields.append(dict(name = "m100", col_id = 6, lower_limit = 30, upper_limit = 200, delta_gran = 5, exhaust_search_step = 4))
fields.append(dict(name = "b100", col_id = 7, lower_limit = b100_lower_limit, upper_limit = b100_upper_limit, delta_gran = 30, exhaust_search_step = 4))
fields.append(dict(name = "tau", col_id = 8, lower_limit = 0, upper_limit = 70000, delta_gran = 500, exhaust_search_step = 6))

rule_no = 0
rules = []
busiest_rule_used_times = 0
row_id = 0


def write_rule_file():
    global next_rule_sn
    global rules
    global output_dir
    global rule_to_tweak
    global working_on_rule
    global mrif_update_rate
    filename = output_dir + '/' + str(next_rule_sn)
    f = open(filename, 'w')
    next_rule_sn += 1
    print >>f, "%d,%d" % (rule_no, mrif_update_rate)
    row_id = 0
    for rule in rules:
        s = ""
        if row_id == working_on_rule:
            for col in rule_to_tweak:
                if s != "":
                    s += ","
                s += str(col)
        else:
            for col in rule:
                if s != "":
                    s += ","
                s += str(col)
        print >>f, s
        row_id += 1

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
        if debug >= 2:
            print "Read in rule", new_rule

        rules.append(new_rule)
        if not row_id in excluded_rules and new_rule[used_times_col_id] > busiest_rule_used_times:
            busiest_rule_used_times = new_rule[used_times_col_id]
            busiest_rule = new_rule
            busiest_rule_id = row_id

        row_id += 1

if debug > 0:
    print 'Busiest rule ID: %d' % (busiest_rule_id)

if working_on_rule != -1:
    rule_to_tweak = list(rules[working_on_rule])
else:
    working_on_rule = busiest_rule_id
    rule_to_tweak = list(busiest_rule)


def gen_rules_using_field(field_id):
    if field_id >= len(fields):
        write_rule_file()
        return

    field = fields[field_id]
    if debug >= 1:
        print "Working on field %s" % (field['name'])

    b    = field['upper_limit']
    a    = field['lower_limit']
    gran = field['delta_gran']
    step = field['exhaust_search_step']
    scale_factor = pow(float(b - a) / gran, 1.0 / step)
    if debug >= 1:
        print "scale_factor: %f" % (scale_factor)
    init_val = rules[working_on_rule][field['col_id']]

    if init_val > b or init_val < a:
        print >> sys.stderr, "Warning: out of range of %s value %d, skip processing this field" % (field['name'], init_val)
        gen_rules_using_field(field_id + 1)
        return

    test_range = max(b - init_val, init_val - a, 0)

    delta = gran
    while delta <= test_range:
        if debug >= 1:
            print "Field %s delta: %f" % (field['name'], delta)
        if init_val - delta >= a:
            rule_to_tweak[field['col_id']] = int(init_val - delta)
            gen_rules_using_field(field_id + 1)
        if init_val + delta <= b:
            rule_to_tweak[field['col_id']] = int(init_val + delta)
            gen_rules_using_field(field_id + 1)
        delta *= scale_factor

gen_rules_using_field(0)
print "%d,%d" % (next_rule_sn, working_on_rule)
