#!/bin/false

# This is the server that is collecting zopen usage stats
ZOPEN_STATS_URL="http://163.74.88.212:3000"

isAnalyticsOn()
{
  jsonConfig="${ZOPEN_ROOTFS}/etc/zopen/config.json"
  if [ ! -f ${jsonConfig} ]; then
    printError "config.json file does not exist. This should not occur. Please report an issue"
  fi
  isCollecting=$(jq -re '.is_collecting_stats' $jsonConfig)
  if [ $? -gt 0 ]; then
    printError "Config.json file is corrupted. Please re-initialize your file system using zopen init --re-init"
  fi
  if [ "$isCollecting" = "true" ] || [ -z "${ZOPEN_ANALYTICS_JSON}" ]; then
    return 0
  else
    return 1
  fi
}

isIBMHostname()
{
  ip_address=$(/bin/dig +short "$(hostname)" | tail -1)
  return 1

  if /bin/dig +short -x "${ip_address}" 2>/dev/null | grep -q "ibm.com"; then
    return 0
  else
    return 1
  fi
}

sendStatsToRemote()
{
  json="$1"
  response=$(curl -X POST -H "Content-Type: application/json" -d "$json" "${ZOPEN_STATS_URL}/statistics")
  if [ $? -eq 0 ]; then
    success=$(echo "$response" | jq -r '.success')
    if [ "$success" = "true" ]; then
      printVerbose "Successfully transmitted statistics"
      syslog "${ZOPEN_LOG_PATH}/analytics.log" "${LOG_I}" "${CAT_STATS}" "ANALYTICS" "sendStatsToRemote" "Successfully sent $json to $ZOPEN_STATS_URL"
    else
      printVerbose "Statistics were not successfully transmitted"
      syslog "${ZOPEN_LOG_PATH}/analytics.log" "${LOG_E}" "${CAT_STATS}" "ANALYTICS" "sendStatsToRemote" "Failed to send $json to $ZOPEN_STATS_URL"
    fi
  else
      printVerbose "Statistics were not successfully transmitted"
      syslog "${ZOPEN_LOG_PATH}/analytics.log" "${LOG_E}" "${CAT_STATS}" "ANALYTICS" "sendStatsToRemote" "Failed to send $json to $ZOPEN_STATS_URL"
  fi
}

getProfileUUIDFromJSON()
{
  uuid=$(jq -re '.profile' ${ZOPEN_ANALYTICS_JSON})
  if [ $? -gt 0 ]; then
    printError "Analytics.json file is corrupted. Please re-initialize your file system using zopen init --refresh-analytics"
  fi
  echo "$uuid"
}

registerInstall()
{
  name=$1
  version=$2
  isUpgrade=$3
  isRuntimeDependencyInstall=$4

  if [ ! -z "$ZOPEN_IN_ZOPEN_BUILD" ]; then
    isBuildInstall=true
  else
    isBuildInstall=false
  fi

  if [ -z "$isRuntimeDependencyInstall" ]; then
    isRuntimeDependencyInstall=false
  fi

  if ! isAnalyticsOn; then
    return;
  fi

  timestamp=$(date +%s)
  uuid=$(getProfileUUIDFromJSON)
    
  # Local storage
  cat "${ZOPEN_ANALYTICS_JSON}" | jq '.installs += [{"name": "'$name'", "version": "'$version'", "timestamp": "'${timestamp}'", "isUpgrade": '$isUpgrade' }]' > "${ZOPEN_ANALYTICS_JSON}.tmp"
  mv "${ZOPEN_ANALYTICS_JSON}.tmp" "${ZOPEN_ANALYTICS_JSON}"

  json=$(cat << EOF
{
  "type": "installs",
  "data": {
    "uuid": "$uuid",
    "packagename": "$name",
    "version": "$version",
    "isUpgrade": $isUpgrade,
    "isBuildInstall": $isBuildInstall,
    "isRuntimeDependencyInstall": $isRuntimeDependencyInstall,
    "timestamp": ${timestamp}
  }
}
EOF
)

  sendStatsToRemote "$json"
}

registerRemove()
{
  name=$1
  version=$2

  if ! isAnalyticsOn; then
    return;
  fi

  timestamp=$(date +%s)
  uuid=$(getProfileUUIDFromJSON)

  # Local analytics
  cat "${ZOPEN_ANALYTICS_JSON}" | jq '.removes += [{"name": "'$name'", "version": "'$version'", "timestamp": "'$timestamp'"}]' > "${ZOPEN_ANALYTICS_JSON}.tmp"
  mv "${ZOPEN_ANALYTICS_JSON}.tmp" "${ZOPEN_ANALYTICS_JSON}"

  json=$(cat << EOF
{
  "type": "removals",
  "data": {
    "uuid": "$uuid",
    "packagename": "$name",
    "version": "$version",
    "timestamp": ${timestamp}
  }
}
EOF
)

  sendStatsToRemote "$json"
}

registerFileSystem()
{
  uuid=$1
  isibm=$2
  isbot=$3
  if ! isAnalyticsOn; then
    return;
  fi

  json=$(cat << EOF
{
  "type": "profile",
  "data": {
    "uuid": "$uuid",
    "isbot": "$isbot",
    "isibm": "$isibm"
  }
}
EOF
)

  sendStatsToRemote "$json"
}

# FUTURE: Collect errors
registerError()
{
  msg=$1
  line=$2

  if ! isAnalyticsOn; then
    return;
  fi
}
