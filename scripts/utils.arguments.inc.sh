#!/bin/bash

function argument() {

	local HELP="
Usage: argument [VARIABLE] [LABEL] [--default VALUE] [--invalidate VALUE]... [OPTION]...

    Options:
        -a, --ask          ask anyway, whether value set or not
        -r, --redacted     hide user input and default value
        -s, --silent       avoid standard output, skip by default
        --skip             enforce default value, skip user input
        --save             save variable to user

    Suggested:
        -d, --default      default value used for empty user input
        -i, --invalidate   force domain joining behaviour
"

	local DEFAULT=""
	local REDACTED=""
	local INVALIDATES=""
	local SKIP=""
	local ASK=""
	local SAVE=""
	local SILENT=""
	
	if [[ $# -lt 1 \
	 || "$1" == "help" \
	 || "$1" == "-h" \
	 || "$1" == "--help" ]]
	then
		echo "$HELP"
		exit 1
	fi
	
	local VARIABLE="$1"
	local VALUE=""
	eval "VALUE=\"\$${VARIABLE}\""
	shift
	
	local TEXT="$1"
	if [ "$TEXT" == "" ] ; then
		TEXT="$VARIABLE"
	elif [[ $( echo "$TEXT" | wc -l) > 1 ]] ; then
		echo "$TEXT" | head -n -1
		TEXT=$(echo "$TEXT" | tail -n 1)
	fi
	shift
	
	while [[ $# -gt 0 ]] ; do
		key="$1"
		case $key in

			-d|--default)
			DEFAULT="$2"
			shift
			;;
			-i|--invalidate)
			INVALIDATES=$(printf "$2\n$INVALIDATES")
			shift
			;;
			-r|--redacted)
			REDACTED="true"
			;;
			-a|--ask)
			ASK="true"
			;;
			-s|--silent)
			SILENT="true"
			SKIP="true"
			;;
			--skip)
			SKIP="true"
			;;
			--save)
			SAVE="true"
			;;
			
			# other arguments
			-h|--help|help)
				echo $HELP		
				exit 0
			;;
			
			*)
				echo "Unknown Option: $1" >&2
			;;
		esac
		shift
	done


	# helper function to validate user/system inputs
	function validate() {
		for invalid in $INVALIDATES ; do
			if [ "$1" == "$invalid" ] ; then
				[ -z "$REDACTED" ] && echo "Invalid value: $1" >&2
				return 1
			fi
		done
		return 0
	}	

	function save() {
		[ ! -z "$SAVE" ] && echo "export ${VARIABLE}=\"$1\"" >> ~/.bashrc
	}
	
	# HAS VALUE
	if [ ! -z "$VALUE" ] ; then
		if [[ ! -z "$SKIP" || -z "$ASK" ]] ; then
			if validate "$VALUE" ; then
				if [ -z "$SILENT" ] ; then
					[ -z "$REDACTED" ] \
					 && echo "$TEXT: $VALUE" \
					 || echo "$TEXT: [REDACTED]"
				fi
				save "$VALUE"
				return 0
			fi
			VALUE=""
		else
			DEFAULT="$VALUE"
		fi
	fi	
	
	# HAS DEFAULT VALUE
	if [ ! -z "$DEFAULT" ] ; then
		if [ ! -z "$SKIP" ] ; then
			eval "$VARIABLE=\"\$DEFAULT\""
			save "$DEFAULT"
			if [ -z "$SILENT" ] ; then
				[ -z "$REDACTED" ] \
				 && echo "$TEXT: $DEFAULT" \
				 || echo "$TEXT: [REDACTED]"
			fi
			return 0
		fi
		TEXT="$TEXT [$DEFAULT]"
	fi
	
	
	# prepare correct parameter if redacted
	[ ! -z "$REDACTED" ] && REDACTED="-s"
	
	local valid=""
	local input=""
	until [ ! -z "$valid" ] ; do
		# read user input
		until [ ! -z "$input" ] ; do
			IFS= read -r $REDACTED -p "$TEXT: " input < /dev/tty || return 1
			if [[ -z "$input" && ! -z "$DEFAULT" ]] ; then
				input="$DEFAULT"
			fi
		done
			
		# add missing line break if redacted
		[ ! -z "$REDACTED" ] && echo ""
		
		# check for invalid value
		validate "$input" && valid="true" || input=""
	done
	eval "$VARIABLE=\"\$input\""
	save "$input"
	return 0
}

# run if arguments are given
[[ $# -gt 0 ]] && argument "$@"
