#!/bin/bash
cd "${0%/*}"

# made by JWA
version="0.1 20230211"
script_name="$(basename -- $0)"

############################ FUNCTIONS ############################

fail_help() {
echo "Usage:
  $script_name <host|device> <var> [options]

Modbus/TCP Query Utility     Allows to read/write LOGO variables
  for Siemens LOGO!          that are accessible over Modbus/TCP
Version $version - made by JWA

Requirements:
  mbpoll                Needs to be in PATH variables or in cd
                        Can be obtained as a debian package

Arguments:
  host                  IP or hostname of the Siemens LOGO for Modbus/TCP
  device                Serial device name for connection over Modbus/RTU
                        You may need to add parameters for the serial
                        connection via --args. See 'mbpoll -h' for details
  var                   LOGO variable to query, allowed ranges are:
                          Digital: I1 - I24,  Q1 - Q20,  M1 - M64,
                          Analog:  AI1 - AI8, AQ1 - AQ8, AM1 - AM24,
                          Virtual Memory: V1 - V6808, VW1 - VW425
                        V and VW are the same registers,
                        V will access bitwise, VW will access wordwise

Options:
  -s, --set <value>     Write <value> into the specified variable
                        This is always unsigned integer
                        You can write to every variable except for I and AI
  -a, --address <addr>  Device address in Modbus, defaults to 255 for LOGO
  -b, --args <args>     Additional arguments for mbpoll command
                        Warning: These args are appended after the generated
                        command, so you can override all arguments set by this
                        script. There is no input checking for this parameter
                        and you could escape the address space and may do other
                        unwanted things if you are not careful.
                        Especially you may not want to set -r or -t
  -v, --verbose         Enable debug output
  -d, --dry-run         Do not run the final mbpoll command, just print it
  -h, --help            Print this help and exit

Examples:
  $script_name 10.0.0.11 AM2
  $script_name logo_hostname Q3 --set 1
  $script_name /dev/ttyS0 I2 --args \"-m rtu -R\"
"; exit 3;
}
fail() { printf "$script_name: $1\n" >&2; exit 3; }
fail_usage() { printf "$script_name: $1\n  Type $script_name -h for usage help\n" >&2; exit 3; }

isNum_notEmpty_canNeg="^-?[0-9]+$"
isNum_notEmpty_notNeg="^[0-9]+$"
isNum_canEmpty_canNeg="^-?[0-9]*$"
isNum_canEmpty_notNeg="^[0-9]*$"
isNum() { if ! [[ "$2" =~ $1 ]]; then return 1; fi; return 0; }

############################ SCRIPT BEGIN ############################

p_host="$1"; shift;
p_var="$1"; shift;

if [[ "$p_host" == "-h" ]] || [[ "$p_host" == "--help" ]]; then fail_help; fi;

if [[ -z $p_host ]]; then fail_usage "required argument <host> missing"; fi;
if [[ -z $p_var ]]; then fail_usage "required argument <var> missing"; fi;
#if [[ "$p_host" =~ [^a-zA-Z0-9\.\-_] ]]; then fail_usage "please specify a valid ip address or hostname"; fi;
if [[ "$p_host" =~ [\"\'\ \\] ]]; then fail_usage "argument <host> cannot contain \" \' [SPACE] [BACKSLASH]"; fi;
if [[ "$p_var" =~ [^a-zA-Z0-9\.] ]]; then fail_usage "logo variable can only be alphanumeric"; fi;

p_var_type="${p_var%%[0-9\.]*}"
p_var_id="${p_var##*[!0-9\.]}"

if [[ -z $p_var_type ]]; then fail_usage "no logo variable type specified"; fi;
if [[ -z $p_var_id ]]; then fail_usage "no logo variable number specified"; fi;

VALID_ARGS=$(getopt -o s:a:b:vd --long set:,address:,args:,verbose,dry-run -- "$@")

if [ $? != 0 ] ; then fail_usage "invalid options"; fi

p_mb_address="255"
p_verbose=false
p_dryrun=false
p_mbpcmd_args=""
p_set=""
eval set -- "$VALID_ARGS"
while true; do
	case "$1" in
		-s | --set )     p_set="$2";       shift 2 ;;
		-a | --address ) p_mb_address="$2";  shift 2 ;;
		-b | --args )    p_mbpcmd_args="$2"; shift 2 ;;
		-v | --verbose ) p_verbose=true;     shift ;;
		-d | --dry-run ) p_dryrun=true;      shift ;;
		-- ) shift; break ;;
		* ) break ;;
	esac
done
if ! isNum "$isNum_canEmpty_notNeg" "$p_set"; then fail_usage "parameter write must be numeric"; fi;
if ! isNum "$isNum_notEmpty_notNeg" "$p_mb_address"; then fail_usage "parameter address must be numeric"; fi;

#=== address space Siemens LOGO ===
#
#  LOGO | modbus | first ref | count
#-------+--------+-----------+-------
#  I    | DI     | 1         | 24
#  Q    | Coils  | 8193      | 20
#  M    | Coils  | 8257      | 64
#  AI   | IR     | 1         | 8
#  AQ   | HR     | 513       | 8
#  AM   | HR     | 529       | 24
#  V    | Coils  | 1         | 6808
#  VW   | HR     | 1         | 425
#
#=== data types on modbus registers: ===
#
#  short | datatype | r/w | mbpoll | register name
#--------+----------+-----+--------+------------------
#  DI    | bit      | r   | 1      | Discrete Inputs
#  Coils | bit      | rw  | 0      | Coils
#  IR    | word     | r   | 3      | Input Registers
#  HR    | word     | rw  | 4      | Holding Registers
#

mb_datatype="";
mb_register_offset=0;
mb_max_count=0;

case "$p_var_type" in
	AI ) mb_datatype=3; mb_max_count=8; ;;
	AQ ) mb_datatype=4; mb_max_count=8; mb_register_offset=512; ;;
	AM ) mb_datatype=4; mb_max_count=24; mb_register_offset=528; ;;
	I )  mb_datatype=1; mb_max_count=24; ;;
	Q )  mb_datatype=0; mb_max_count=20; mb_register_offset=8192; ;;
	M )  mb_datatype=0; mb_max_count=64; mb_register_offset=8256; ;;
	V )  mb_datatype=0; mb_max_count=6808; ;;
	VW ) mb_datatype=4; mb_max_count=425; ;;
	* )  fail_usage "logo variable type \"$p_var_type\" is unknown"; ;;
esac

mb_register=$(($mb_register_offset + $p_var_id));
if [[ $p_verbose == true ]]; then printf "=== Address calculation:\n datatype = $mb_datatype, addr_offset = $mb_register_offset, max_count = $mb_max_count\n calculated address = $mb_register\n\n"; fi;

if (( $mb_register < $(( $mb_register_offset + 1 )) )) || (( $mb_register > $(( $mb_register_offset + $mb_max_count )) )); then
	fail_usage "invalid variable number, allowed range: ${p_var_type}1 - ${p_var_type}${mb_max_count}";
fi;

if [[ -n $p_mbpcmd_args ]]; then p_mbpcmd_args=" $p_mbpcmd_args"; fi;

mbpcmd=""
mbpcmd_args="-t $mb_datatype -r $mb_register -a ${p_mb_address//\"}${p_mbpcmd_args//\"} ${p_host//\"}"
if [[ -n $p_set ]]; then
	# write mode
	if [[ "$p_var_type" =~ [I] ]]; then fail_usage "write is not possible on inputs"; fi;
	mbpcmd="mbpoll $mbpcmd_args -- $p_set";
else
	# read mode
	mbpcmd="mbpoll -1 $mbpcmd_args";
fi;

if [[ $p_verbose == true ]]; then printf "=== mbpoll command: $mbpcmd\n\n"; fi;
if [[ $p_dryrun == true ]]; then echo $mbpcmd ""; exit 0; fi;

unset t_std t_err;
eval "$( $mbpcmd \
      2> >(t_err=$(cat); typeset -p t_err) \
       > >(t_std=$(cat); typeset -p t_std) )"
if [[ $p_verbose == true ]]; then printf "=== mbpoll output:\n$t_std\n\n"; fi;
if [[ -n $t_err ]]; then fail "$t_err"; fi;

t_lastline=$(printf -- "$t_std" | grep "." | tail -1)
if [[ $p_verbose == true ]]; then printf "=== last line of output:\n$t_lastline\n\n"; fi;

if [[ -n $p_set ]]; then
	echo "$t_lastline";
	exit 0;
fi;
t_final=$(grep -Eo '[0-9]+$' <<< "$t_lastline")

if [[ $p_verbose == true ]]; then
	echo "${p_var_type}${p_var_id} = $t_final";
else
	echo "$t_final";
fi;
exit 0;

############################ SCRIPT EOF ############################