#!/bin/bash

# made by JWA
version="0.1 20230211"
script_name="$(basename -- $0)"

N_OK=0; N_WARN=1; N_CRIT=2; N_UNKNOWN=3;

############################ FUNCTIONS ############################

fail_help() {
echo "Usage:
  $script_name -H <host> -v <var> -w <warning> -c <critical>

check_logo:  Nagios check plugin for querying and matching Siemens LOGO!
             inputs/outputs against thresholds or threshold ranges

Requirements:
  ./modbus_logo.sh       Script has to be in the current directory!

Options:
  -H, --host <host>      IP or hostname of the Siemens LOGO
  -v, --var <var>        LOGO variable to query
                         See 'modbus_logo.sh -h' for details
  -a, --args <args>      (Optional) arguments for modbus_logo.sh
  -w, --warn <warning>   Warning threshold or range
                         Range is seperated by : (e.g. -1:29)
  -c, --crit <critical>  Critical threshold or range
                         Range is seperated by : (e.g. -10:40)
  -d, --desc <desc>      (Optional) field description for output
  -f, --factor <value>   Multiplies the raw result for final output by
                         <value>. Because of the float limitations
                         in bash this happens after the thresholds are
                         applied. So you need to specify them for raw value.
                         Optional, defaults to 1
  -u, --unit <unit>      Optional, gets appended to the value for output
  -i, --invert           Inverts the comparison logic for the thresholds.
                         The default behaviour for warning or critical is
                         to report a warn/crit if the value is larger
                         than threshold. If -i is set, a warn/crit will
                         be reported when the value is lower than threshold.
                         CAUTION: Invert does not apply to ranges because you
                         can just swap the parameters around and get the same
                         functionality. The default behaviour for ranges is
                         to report a warn/crit if the value is outside the
                         range. By writing the higher number first you get
                         warn/crit if value is inside the range!
  -h, --help             Print this help

Examples:
  $script_name -H 10.0.0.11 -v AM2 -c 190:230 -w 195:210 -f 0.1 -u \"°C\"
    this will output with exit code 0: OK - LOGO variable AM2: 19.5 °C
    if value falls below 195 WARNING will be reported, below 193 CRITICAL
  $script_name -H 10.0.0.11 -v I9 -c 0:0 -w 0:0
    this will report critical if I9 = 1, ok if it is 0
"; exit $N_UNKNOWN;
}
fail() { printf "UNKNOWN: $1\n" >&2; exit $N_UNKNOWN; }
fail_usage() { printf "$script_name: $1\n  Type $script_name -h for usage help\n" >&2; exit $N_UNKNOWN; }

isNum_notEmpty_canNeg="^-?[0-9]+$"
isNum_notEmpty_notNeg="^[0-9]+$"
isNum_canEmpty_canNeg="^-?[0-9]*$"
isNum_canEmpty_notNeg="^[0-9]*$"
isNum() { if ! [[ "$2" =~ $1 ]]; then return 1; fi; return 0; }

############################ SCRIPT BEGIN ############################

VALID_ARGS=$(getopt -o H:v:a:w:c:d:f:u:ih --long host:,var:,args:,warn:,crit:,desc:,factor:,unit:,invert,help -- "$@")
if [ $? != 0 ] ; then fail_usage "invalid options"; fi


p_host=; p_var=; p_args=;
p_warn=; p_w1=; p_w2=;
p_crit=; p_c1=; p_c2=;
p_factor=; p_unit=; p_desc=;
p_invert=false

eval set -- "$VALID_ARGS"
while true; do
	case "$1" in
		-H | --host )   p_host="$2";   shift 2 ;;
		-v | --var )    p_var="$2";    shift 2 ;;
		-a | --args )   p_args="$2";   shift 2 ;;
		-w | --warn )   p_warn="$2";   shift 2 ;;
		-c | --crit )   p_crit="$2";   shift 2 ;;
		-d | --desc )   p_desc="$2";   shift 2 ;;
		-f | --factor ) p_factor="$2"; shift 2 ;;
		-u | --unit )   p_unit="$2";   shift 2 ;;
		-i | --invert ) p_invert=true; shift ;;
		-h | --help )   fail_help;       shift ;;
		-- ) shift; break ;;
		* ) break ;;
	esac
done

p1=; p2=;
threshold_input() {
	p1=; p2=;
	if [[ "$1" =~ ^-?[0-9]+:-?[0-9]+$ ]]; then
		p1=${1%:*}; p2=${1#*:};
		if ! isNum "$isNum_notEmpty_canNeg" "$p1" || ! isNum "$isNum_notEmpty_canNeg" "$p1"; then fail_usage "both parameters in range <${2}> must be numeric"; fi;
		if (( $p1 > $p2 )); then fail_usage "range <${2}>: first value is larger than second one"; fi;
	else
		if ! isNum "$isNum_notEmpty_canNeg" "$1"; then fail_usage "parameter <${2}> must be numeric and cannot be empty"; fi;
	fi;
}

threshold_input "$p_warn" "warning";
if [[ -n $p1 ]]; then p_w1=$p1; p_w2=$p2; fi;

threshold_input "$p_crit" "critical";
if [[ -n $p1 ]]; then p_c1=$p1; p_c2=$p2; fi;

mlscmd="./modbus_logo.sh ${p_host//\"} ${p_var//\"}${p_args//\"}"
unset t_std t_err;
eval "$( $mlscmd \
      2> >(t_err=$(cat); typeset -p t_err) \
       > >(t_std=$(cat); typeset -p t_std) )"
#if [[ $p_verbose == true ]]; then printf "=== mbpoll output:\n$t_std\n\n"; fi;
if [[ -n $t_err ]]; then fail "$t_err"; fi;

if ! isNum "$isNum_notEmpty_notNeg" "$t_std"; then fail "non-numeric output from modbus_logo.sh:\n$t_std"; fi;

val=$t_std; val_output=$val;
if [[ -n $p_factor ]]; then val_output=$(awk "BEGIN {x=$val; y=$p_factor; print x*y}"); fi;
if [[ -n $p_unit ]]; then val_output+=" $p_unit"; fi;


# Arguments: $1 = N_STATUS, $2 = status human readable
report_status() {
	if [[ -z $p_desc ]]; then p_desc="LOGO variable $p_var:"; fi;
	echo "$2 - $p_desc $val_output";
	exit $1;
}

# Arguments: $1 = range 1, $2 = range 2, $3 = threshold, $4 = N_STATUS, $5 = status human readable
match_val() {
	if [[ -n $1 ]]; then
		# range comparison
		if (( $val < $1 )) || (( $val > $2 )); then report_status $4 "$5"; fi;
	else
		# threshold comparison
		if ! [[ $p_invert == true ]]; then
			# normal mode
			if (( $val > $3 )); then report_status $4 "$5"; fi;
		else
			# inverted mode
			if (( $val < $3 )); then report_status $4 "$5"; fi;
		fi;
	fi;
}


match_val $p_c1 $p_c2 $p_crit $N_CRIT "CRITICAL";
match_val $p_w1 $p_w2 $p_warn $N_WARN "WARNING";

report_status $N_OK "OK";

fail "script should never reach this point";
exit $N_UNKNOWN;

############################ SCRIPT EOF ############################