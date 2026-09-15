# GlobalProtect has no cask in Homebrew, so this repository doubles as a tap that carries one.
# The company portal at upstage.gpcloudservice.com serves the pkg through a redirect to Palo Alto's public
# bucket, so this cask fetches the same file the portal hands out. To bump the version, run
#   curl -sI 'https://upstage.gpcloudservice.com/global-protect/getmsi.esp?version=64&platform=mac' | grep -i location
# and update the version and sha256 below to match.
cask "globalprotect" do
  version "6.3.3-650"
  sha256 "e78329776a08320696e96f335b995d4f0205ab1379482bbf9df9f54408e7ccf2"

  url "https://pan-gp-client.s3.dualstack.us-west-2.amazonaws.com/#{version}/GlobalProtect.pkg"
  name "GlobalProtect"
  desc "Palo Alto Networks GlobalProtect VPN client"
  homepage "https://upstage.gpcloudservice.com/"

  depends_on macos: :big_sur

  # The installer leaves the "GlobalProtect System extensions" choice off by default. macOS 11 and later
  # cannot load the kernel extensions, so the client only works with that choice on.
  pkg "GlobalProtect.pkg",
      choices: [
        {
          "choiceIdentifier" => "third",
          "choiceAttribute"  => "selected",
          "attributeSetting" => 1,
        },
      ]

  uninstall script:  {
              executable:   "/Applications/GlobalProtect.app/Contents/Resources/uninstall_gp.sh",
              sudo:         true,
              must_succeed: false,
            },
            pkgutil: "com.paloaltonetworks.globalprotect.pkg"

  zap trash: [
    "~/Library/Application Support/PaloAltoNetworks",
    "~/Library/Group Containers/group.PXPZ95SK77.com.paloaltonetworks.GlobalProtect.client",
    "~/Library/Logs/PaloAltoNetworks",
    "~/Library/Preferences/com.paloaltonetworks.GlobalProtect.client.plist",
    "~/Library/Preferences/com.paloaltonetworks.GlobalProtect.pangps.plist",
    "~/Library/Preferences/com.paloaltonetworks.GlobalProtect.settings.plist",
  ]

  caveats <<~EOS
    Exosphere antivirus must be installed before GlobalProtect will pass the network check.
    On first launch enter the portal address:  upstage.gpcloudservice.com
    Then approve the client in System Settings > General > Login Items & Extensions:
      - Network Extensions: allow GlobalProtect
      - Allow in the Background: enable Palo Alto Networks
    and allow GlobalProtect under System Settings > Notifications.
  EOS
end
