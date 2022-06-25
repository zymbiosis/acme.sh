#!/usr/bin/env sh

#
# ENOM_Username="account ID"
#
# ENOM_Password="API Token"
#

enom_URL="https://reseller.enom.com/interface.asp"

########  Public functions #####################

dns_enom_add() {
  fulldomain=$1
  txtvalue=$2

  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ENOM_Username="${ENOM_Username:-$(_readaccountconf_mutable ENOM_Username)}"
  ENOM_Password="${ENOM_Password:-$(_readaccountconf_mutable ENOM_Password)}"

  _debug ENOM_Username "$ENOM_Username"
  _debug ENOM_Password "$ENOM_Password"

  if [ -z "$ENOM_Username" ] || [ -z "$ENOM_Password" ]; then
    ENOM_Username=""
    ENOM_Password=""
    _err "You didn't specify enom username or api token (password)."
    return 1
  fi

  _saveaccountconf_mutable ENOM_Username "$ENOM_Username"
  _saveaccountconf_mutable ENOM_Password "$ENOM_Password"

  _debug "First get the tld"
  if ! _get_tld "$fulldomain"; then
    _err "Invalid Domain"
    return 1
  fi
  _debug tld "$tld"

  sld=$(echo "$fulldomain" | sed -r 's/.*\.([^.]+\.[^.]+)$/\1/' | sed -r "s/.$tld//")
  _debug sld "$sld"

  acme_Hostname=$(echo "$fulldomain" | sed -r "s/\.$sld\.$tld//")
  _debug acme_Hostname "$acme_Hostname"

  #Get all current records
  _enom_rest GET "GetHosts" "uid=${ENOM_Username}&pw=${ENOM_Password}&SLD=${sld}&TLD=${tld}&ResponseType=text"

  hostData="$response"
  _debug hostData "$hostData"

  if [ -z "$response" ] || [! _contains "${response}" 'error']; then
    _err "Unable to retrieve host records"
    return 0
  fi

  # Now lets put together the query string for setting the hosts
  hostnameNum=0
  postData=""
  for line in $hostData
  do
    if [ ! "$line" = "${line#HostName}" ] || 
       [ ! "$line" = "${line#Address}" ] || 
       [ ! "$line" = "${line#RecordType}" ] || 
       [ ! "$line" = "${line#MXPref}" ]; then
      line=$(echo "$line" | sed -r 's/\r$//')
      #_debug line "$line"
      lineKey=$(echo "$line" | sed -r "s/=(.*)//")
      lineHostname=$(echo "$line" | sed -r "s/HostName[0-9]+=//")

      #Check to see if this is an existing acme challenge, if so get the number
      if [ "$lineHostname" = "$acme_Hostname" ]; then
        hostnameNum=$(echo "$line" | sed -r "s/HostName//" | sed -r "s/=${acme_Hostname}//")
        #_debug hostnameNum "$hostnameNum"
      fi

      #If the number for an existing acme challenge exists, then update
      if [ "$lineKey" = "Address$hostnameNum" ]; then
        line="Address$hostnameNum=$txtvalue"
      fi

      #echo "$postData&$line"
      postData="$postData&$line"
      #_debug postData "$postData"
    fi
  done

  postData="uid=${ENOM_Username}&pw=${ENOM_Password}&SLD=${sld}&TLD=${tld}${postData}"
  _debug postData "$postData"

  _info "Adding TXT record to ${fulldomain}"
  _enom_rest GET "SetHosts" "$postData"

  if ! _contains "${response}" 'error'; then
    return 0
  fi
  _err "Could not create resource record, check logs"
  _err "${response}"
  return 1
}


####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _tld=domain.com
_get_tld() {
  domain=$1

  tld=$(echo "${domain}" | sed -r "s/ .*//; s/.*\.//")
  return 0;
}

#returns
# response
_enom_rest() {
  m=$1
  c="$2"
  data="$3"
  _debug "$c"

  export _H1="Content-Type: application/x-www-form-urlencoded"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$enom_URL/$c" "" "$m")"
  else
    response="$(_get "${enom_URL}?command=${c}&${data}")"
  fi

  #_debug response "${response}"
  return 0
}