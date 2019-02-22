# iOS IPA Resign 

easily re-sign your iOS IPA with new provisioning profiles


# Use

`./resign.sh "IPA Source File Path" "provision profile path" "destination dir" "iPhone Developer: Signing Identity (XXXXXXXXXX)"`

For avaialable signing identies run: 
`security find-identity -p codesigning -v | grep -o '".*"' | tr -d '"'`

# Requirements

* macOS computer
* Apple Xcode