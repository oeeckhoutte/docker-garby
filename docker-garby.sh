#!/bin/sh

logFile="syslog"
maxSecondsOld=3600

containerRemoval(){
  containerCount=$(docker ps -qa | wc -l)

  if [ "$containerCount" -lt 1 ]; then
    logAllThings "No containers found."
    return
  fi

  for con in $(docker ps -qa); do
    # yeah, all this 'docker inspect' stuff should probably be done just once
    containerDead=$(docker inspect -f '{{.State.Dead}}' "$con")
    containerFinished=$(docker inspect -f '{{.State.FinishedAt}}' "$con")
    containerImage=$(docker inspect -f '{{.Image}}' "$con")
    containerName=$(docker inspect -f '{{.Name}}' "$con")
    containerRunningState=$(docker inspect -f '{{.State.Running}}' "$con")
    containerStatus=$(docker inspect -f '{{.State.Status}}' "$con")
    imageName=$(docker inspect -f '{{.RepoTags}}' "$containerImage")
    timeDiffOutput=$(timeDiff "$containerFinished")
    echo "$containerImage" >> "$usedImagesLog"
    remove=0

    if [ "$containerStatus" = "created" -a "$containerRunningState" = "false" ]; then
      logAllThings "Container $containerName ($con) is in 'created' state."
      remove=1
    fi

    if [ "$containerDead" = "true" -a "$containerRunningState" = "false" ]; then
      logAllThings "Container $containerName ($con) is in 'dead' state."
      remove=1
    fi

    if [ "$timeDiffOutput" -gt $maxSecondsOld -a "$containerRunningState" = "false" ]; then
      logAllThings "Container $containerName ($con) finished $timeDiffOutput seconds ago."
      remove=1
    fi

    if [ "$remove" = 1 ]; then
      logAllThings "Container $containerName ($con) used image $imageName."

      docker rm "$con" 2>/dev/null 1>&2
      if [ "$?" -eq 0 ]; then
        logAllThings "Container $containerName ($con) removed."
      else
        logAllThings "ERR: Container $containerName ($con) was not removed."
      fi
    fi

  done
}

defineTmpFiles(){
  if [ -z "$TMP" ]; then
    export TMP='/tmp'
  fi
  allContainersLog=$(mktemp -p "${TMPDIR:-$TMP}" allContainers.XXXXXX)
  allImagesLog=$(mktemp -p "${TMPDIR:-$TMP}" allImages.XXXXXX)
  allImagesTmpLog=$(mktemp -p "${TMPDIR:-$TMP}" allImagesTmp.XXXXXX)
  removeImagesLog=$(mktemp -p "${TMPDIR:-$TMP}" removeImages.XXXXXX)
  usedImagesLog=$(mktemp -p "${TMPDIR:-$TMP}" usedImages.XXXXXX)
  usedImagesTmpLog=$(mktemp -p "${TMPDIR:-$TMP}" usedImagesTmp.XXXXXX)
}

gatherBasicInfo(){
  allContainers=$(docker ps --no-trunc -qa)
  allImages=$(docker images --no-trunc -q)

  echo "$allContainers" > "$allContainersLog"
  echo "$allImages" > "$allImagesLog"

  if test -e "$usedImagesLog"; then
    rm "$usedImagesLog"
  fi

  touch "$usedImagesLog"
}

imageRemoval(){
  imageCount=$(docker ps -qa | wc -l)

  if [ "$imageCount" -lt 1 ]; then
    logAllThings "No images found."
    return
  fi

  sort "$allImagesLog" | uniq > "$allImagesTmpLog"
  sort "$usedImagesLog" | uniq > "$usedImagesTmpLog"
  comm -23 "$allImagesTmpLog" "$usedImagesTmpLog" > "$removeImagesLog"

  while read line
  do
    imageName=$(docker inspect -f '{{.RepoTags}}' "$line")
    logAllThings "Image $imageName ($line) unused."
    docker rmi -f "$line" 2>/dev/null 1>&2

    if [ "$?" -eq 0 ]; then
      logAllThings "Image $imageName ($line) removed."
      else
      logAllThings "ERR: Image $imageName ($line) was not removed."
    fi
    done < "$removeImagesLog"
}

logAllThings(){
  logDate=$(LC_ALL=C date -u +%Y%m%d)
  logDateEntry=$(LC_ALL=C date -u +%Y%m%d%H%M%S)
  if [ "$logFile" = "syslog" ]; then
    logger -i -t 'docker-garby' -p 'user.info' "$1"
    elif [ -z "$logFile" ]; then
    echo "[$logDateEntry] $1"
    else
    echo "[$logDateEntry] $1" >> "$logFile-$logDate"
  fi
}

removeTmpFiles(){
  rm "$allContainersLog"
  rm "$allImagesLog"
  rm "$allImagesTmpLog"
  rm "$removeImagesLog"
  rm "$usedImagesLog"
  rm "$usedImagesTmpLog"
}

timeDiff(){
  containerTime="$(echo "$1" | sed -e 's/ +.*/Z/' -e 's/ /T/')"
  dateEpoch=$(LC_ALL=C date -u +%s)
  convertToEpoch="$(LC_ALL=C date -u -d "$containerTime" +%s)"

  if [ "$convertToEpoch" -lt 0 ]; then
    # this is negative, which means no exit state"
    containerEpoch="$dateEpoch"
    else
    containerEpoch="$convertToEpoch"
  fi

  timeDiffSeconds="$((dateEpoch - containerEpoch))"
  echo "$timeDiffSeconds"
}

defineTmpFiles
gatherBasicInfo
containerRemoval
imageRemoval
removeTmpFiles
