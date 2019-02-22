#!/bin/bash

# -----------------------------------------------------------------------------
#
# Author:    Mike Elston mike@notsle.com
# Created:   2019.02.22
# #
# -----------------------------------------------------------------------------
# Permission is hereby granted, free of charge, to any person obtaining 
# a copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation 
# the rights to use, copy, modify, merge, publish, distribute, sublicense, 
# and/or sell copies of the Software, and to permit persons to whom the 
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included 
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS 
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF 
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY 
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, 
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# Please let us know about any improvements you make to this script!
# -----------------------------------------------------------------------------

IPA=$1
PROVISIONING_PROFILE=$2
DESTINATION_PATH=${3%/}
SIGNING_IDENTITY=$4

#Args processing
if [ "$IPA" == "" ];
then
    echo 'Usage: '
    echo '    ./resign.sh "IPA Source File Path" "provision profile path" "destination dir" "iPhone Developer: Signing Identity (XXXXXXXXXX)"'''
    echo ' '
    echo 'For avaialable signing identies run: '
    echo '    security find-identity -p codesigning -v | grep -o '\''".*"'\'' | tr -d '\''"'\'''
    exit 1
fi

if [ ! -f "$IPA" ];
then
    echo "Cannot find IPA, given path: ${IPA}"
    exit 1
fi

if [ ! -f "$PROVISIONING_PROFILE" ];
then
    echo "Cannot find Provisioning profile, given path: ${PROVISIONING_PROFILE}"
    exit 1
fi

if [ "$DESTINATION_PATH" == "" ];
then
    echo "Usage: sh resign.sh ipa_path provisioning_path destination_path signing_identity"
    exit 1
fi

if [ ! -d "$DESTINATION_PATH" ];
then
    mkdir -p $DESTINATION_PATH
fi

codes_availables=$(security find-identity -p codesigning -v | grep -o '".*"' | tr -d '"')

# if [ "$SIGNING_IDENTITY" == "" ] || [[ $codes_availables != *$SIGNING_IDENTITY* ]];
# then
#   echo "The signing identity not exists."
#   exit 1
# fi

IPA_CONTENT_PATH="ipa_content"

#Unzip ipa
if [ -d $IPA_CONTENT_PATH ]
then
    rm -rf $IPA_CONTENT_PATH
fi
unzip -q ${IPA} -d $IPA_CONTENT_PATH


#Data analysis
echo "Analysing data..."
PROVISIONING_PROFILE_DECRYPTED="${DESTINATION_PATH}/${PROVISIONING_PROFILE}.plist"

echo $PROVISIONING_PROFILE_DECRYPTED
security cms -D -i "${PROVISIONING_PROFILE}" > "${PROVISIONING_PROFILE_DECRYPTED}"

APP_NAME=$(ls -1 $IPA_CONTENT_PATH/Payload)
echo "APP Name: ${APP_NAME}"

CURRENT_BUNDLE_IDENTIFIER=`/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$IPA_CONTENT_PATH/Payload/$APP_NAME/Info.plist"`
NEW_BUNDLE_IDENTIFIER=`egrep -a -A 2 application-identifier $PROVISIONING_PROFILE | grep string | sed -e 's/<string>//' -e 's/<\/string>//' -e 's/ //' | awk '{split($0,a,"."); print a[2] "." a[3] "." a[4]}'`
echo "CURRENT_BUNDLE_IDENTIFIER=$CURRENT_BUNDLE_IDENTIFIER">&2
echo "NEW_BUNDLE_IDENTIFIER=$NEW_BUNDLE_IDENTIFIER">&2
if [ "$CURRENT_BUNDLE_IDENTIFIER" != "$NEW_BUNDLE_IDENTIFIER" ]; 
then 
   echo "Update the bundle identifier"
   `/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $NEW_BUNDLE_IDENTIFIER" "$IPA_CONTENT_PATH/Payload/$APP_NAME/Info.plist"`
fi


TEAM_IDENTIFIER=$(/usr/libexec/Plistbuddy -c "Print :TeamIdentifier:0" "${PROVISIONING_PROFILE_DECRYPTED}")
echo "Team Identifier: ${TEAM_IDENTIFIER}"

APPLICATION_IDENTIFIER_PREFIX=$(/usr/libexec/Plistbuddy -c "Print :ApplicationIdentifierPrefix:0" "${PROVISIONING_PROFILE_DECRYPTED}")
echo "Application Identifier Prefix: ${APPLICATION_IDENTIFIER_PREFIX}"

echo "Signing Identity: ${SIGNING_IDENTITY}"

BUNDLE_IDENTIFIER=$(/usr/libexec/Plistbuddy -c "Print :CFBundleIdentifier" "$IPA_CONTENT_PATH/Payload/$APP_NAME/Info.plist")
echo "Bundle Identifier: ${BUNDLE_IDENTIFIER}"

PROVISIONING_DEVICES=$(/usr/libexec/Plistbuddy -c "Print :ProvisionedDevices" "${PROVISIONING_PROFILE_DECRYPTED}")
if [ "$PROVISIONING_DEVICES" == "" ];
then
    echo "Provisioning profile WITHOUT attached devices"
    HAS_DEVICES="NO"
else
    echo "Provisioning profile WITH attached devices"
    HAS_DEVICES="YES"
fi
PROVISIONING_GET_TASK_ALLOW=$(/usr/libexec/Plistbuddy -c "Print :Entitlements:get-task-allow" "${PROVISIONING_PROFILE_DECRYPTED}")
echo "Provisioning get-task-allow: ${PROVISIONING_GET_TASK_ALLOW}"

rm "${PROVISIONING_PROFILE_DECRYPTED}"


#Cleaning Ipacontent files
rm -rf "$IPA_CONTENT_PATH/Payload/$APP_NAME/_CodeSignature/"
rm -f "$IPA_CONTENT_PATH/Payload/$APP_NAME/embedded.mobileprovision"


#Setting a new identity
# echo "${PROVISIONING_PROFILE}" "$IPA_CONTENT_PATH/Payload/$APP_NAME/embedded.mobileprovision"
cp "${PROVISIONING_PROFILE}" "$IPA_CONTENT_PATH/Payload/$APP_NAME/embedded.mobileprovision"
APP_ENTITLEMENTS="$DESTINATION_PATH/Entitlements.plist"
if [ -f ${APP_ENTITLEMENTS} ]
then
    rm -f ${APP_ENTITLEMENTS}
fi

/usr/libexec/PlistBuddy -c "Add :application-identifier string ${APPLICATION_IDENTIFIER_PREFIX}.${BUNDLE_IDENTIFIER}" "${APP_ENTITLEMENTS}"

if [ ${HAS_DEVICES} == "NO" ] && [ ${PROVISIONING_GET_TASK_ALLOW} == "false" ]
then
    /usr/libexec/PlistBuddy -c "Add :beta-reports-active bool true" "${APP_ENTITLEMENTS}"
fi

/usr/libexec/PlistBuddy -c "Add :get-task-allow bool ${PROVISIONING_GET_TASK_ALLOW}" "${APP_ENTITLEMENTS}"
/usr/libexec/PlistBuddy -c "Add :keychain-access-groups array" "${APP_ENTITLEMENTS}"
/usr/libexec/PlistBuddy -c "Add :keychain-access-groups:0 string ${APPLICATION_IDENTIFIER_PREFIX}.${BUNDLE_IDENTIFIER}" "${APP_ENTITLEMENTS}"
cp "${APP_ENTITLEMENTS}" "$IPA_CONTENT_PATH/Payload/$APP_NAME/archived-expanded-entitlements.xcent"


#Resinging
echo "Resigning the app with identity: ${SIGNING_IDENTITY}"
if [ -d "$IPA_CONTENT_PATH/Payload/$APP_NAME/Frameworks" ];
then
    for SWIFT_LIB in $(ls -1 "$IPA_CONTENT_PATH/Payload/$APP_NAME/Frameworks"); do
        codesign --force --sign "${SIGNING_IDENTITY}" --verbose "$IPA_CONTENT_PATH/Payload/$APP_NAME/Frameworks/${SWIFT_LIB}"
    done
fi
codesign --force --entitlements "${APP_ENTITLEMENTS}" --sign "${SIGNING_IDENTITY}" "$IPA_CONTENT_PATH/Payload/$APP_NAME" --verbose
codesign --verify --verbose --deep --no-strict "$IPA_CONTENT_PATH/Payload/$APP_NAME"


#Packaging
IPA_RESIGNED_PATH="${DESTINATION_PATH}/${IPA%.*}_RESIGNED.ipa"
cd $IPA_CONTENT_PATH
zip -qr "../RESIGNED.ipa" .
cd ..
mv "RESIGNED.ipa" "${IPA_RESIGNED_PATH}"

#Cleaning tmp files
rm -rf $IPA_CONTENT_PATH
rm $APP_ENTITLEMENTS


#Output
echo
echo "***************************"
echo
if [ ${HAS_DEVICES} == "NO" ] && [ ${PROVISIONING_GET_TASK_ALLOW} == "false" ]
then
    echo "IPA succesfully signed for AppStore Distribution. This binary is NOT COMPATIBLE for AdHoc Deployment or Development."
elif [ ${HAS_DEVICES} == "YES" ] && [ ${PROVISIONING_GET_TASK_ALLOW} == "true" ]
then
    echo "IPA succesfully signed for AdHoc Distribution."
else
    echo "IPA succesfully signed for Development Distribution. This binary is NOT COMPATIBLE for AppStore Deployment or Adhoc Distribution."
fi

echo
echo "Result IPA: ${IPA_RESIGNED_PATH}"
echo
echo "***************************"
echo
