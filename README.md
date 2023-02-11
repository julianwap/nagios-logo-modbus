## Nagios check plugin for Siemens LOGO

This plugin consists of two bash scripts to read and process the inputs and outputs of your Siemens LOGO!8 over ModBus/TCP.

Requirements:
- [mbpoll](https://github.com/epsilonrt/mbpoll) (Usually part of your distros apt-repo)
- ModBus Server needs to be enabled on the LOGO and your machines IP has to be in allowed IP list.

## modbus_logo.sh
This script provides an interface to mbpoll. It translates the addresses, sets some defaults and builds the mbpoll command.
Further it processes the output to extract the raw value.

Simple call for Input I3 on Logo IP 10.0.0.11:
```bash
./modbus_logo.sh 10.0.0.11 I3
#    returns 0 or 1
```

You could also write to an output:
```bash
./modbus_logo.sh 10.0.0.11 Q7 -s 1
```

Full Usage:
```
  modbus_logo.sh <host|device> <var> [options]

Modbus/TCP Query Utility     Allows to read/write LOGO variables
  for Siemens LOGO!          that are accessible over Modbus/TCP

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
  modbus_logo.sh 10.0.0.11 AM2
  modbus_logo.sh logo_hostname Q3 --set 1
  modbus_logo.sh /dev/ttyS0 I2 --args \"-m rtu -R\"
```

## check_logo.sh
This is the nagios check plugin which runs modbus_logo.sh (needs to be in same directory) and compares the result against provided warning and critical levels. 

Check if a temperature sensor with a factor of 0.1 is inside a range of values:
```bash
check_logo.sh -H 10.0.0.11 -v AM2 -c 190:230 -w 195:210 -f 0.1 -u "°C"
#    this will output with exit code 0: OK - LOGO variable AM2: 19.5 °C
#    if value falls below 195 WARNING will be reported, below 193 CRITICAL
```

Full usage:
```
  check_logo.sh -H <host> -v <var> -w <warning> -c <critical>

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
  check_logo.sh -H 10.0.0.11 -v AM2 -c 190:230 -w 195:210 -f 0.1 -u "°C"
    this will output with exit code 0: OK - LOGO variable AM2: 19.5 °C
    if value falls below 195 WARNING will be reported, below 193 CRITICAL
  check_logo.sh -H 10.0.0.11 -v I9 -c 0:0 -w 0:0
    this will report critical if I9 = 1, ok if it is 0
```
