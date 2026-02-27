# ShadowGuard 🛡️

**A powerful, system-wide MITM ad-blocker and privacy shield for iOS**

> ⚠️ **Personal Use Only** - This app uses MITM proxy for deep HTTPS inspection. Requires certificate trust.

![iOS 15.0+](https://img.shields.io/badge/iOS-15.0+-blue.svg)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)
![SwiftUI](https://img.shields.io/badge/SwiftUI-4.0-green.svg)

## Features

### 🔒 MITM Core Engine + DNS Blocking
- **MITM Proxy**: Full HTTPS content inspection for dynamic ad blocking (YouTube, Instagram, etc.)
- **DNS-Level Blocking**: Additional layer - blocks ad domains at DNS level
- **Root CA Generation**: Creates a unique self-signed root certificate for your device
- **Dynamic Certificate Generation**: On-the-fly certificate creation for intercepted domains
- **TLS 1.2/1.3 Support**: Modern TLS protocol support with proper SNI handling
- **Certificate Pinning Bypass**: Gracefully handles pinned domains by bypassing interception

### 🚫 Powerful Filtering
- **Popular Blocklists**: EasyList, EasyPrivacy, AdGuard Base, StevenBlack Hosts, and more
- **AdBlock Plus Syntax**: Full support for ABP filter syntax
- **uBlock Origin Extended**: Partial support for uBO extended syntax
- **Custom Rules**: Create your own block, allow, and redirect rules
- **Regex Support**: Advanced pattern matching with regular expressions
- **Cosmetic Filtering**: Element hiding via CSS selectors (experimental)

### 🎨 Futuristic UI
- **Dark Mode First**: Cyberpunk/neon aesthetic with glassmorphism effects
- **Animated Backgrounds**: Subtle particle and gradient animations
- **Responsive Design**: Optimized for all iPhone sizes (SE to Pro Max)
- **Real-time Stats**: Live blocking statistics and bandwidth savings

### ⚡ Performance Optimized
- **Trie Data Structure**: O(m) domain lookup where m = domain length
- **Bloom Filter**: Fast negative lookups to skip non-blocked domains
- **Early Packet Drop**: Blocked connections dropped at DNS/SNI level
- **Minimal Battery Impact**: Only inspects necessary packet headers

### 📊 Comprehensive Logging
- **Real-time Traffic Logs**: Color-coded entries for blocked, allowed, TLS, and errors
- **Search & Filter**: Find specific requests quickly
- **Export Capability**: Share logs for debugging

## Requirements

- **iOS 15.0** or later (optimized for iOS 17+)
- **Xcode 15.0** or later
- **Apple Developer Account** (free or paid)
- **Mac** for building

## Installation

### Step 1: Clone and Open Project

```bash
git clone <repository-url>
cd adblockerios
open ShadowGuard.xcodeproj
```

### Step 2: Configure Signing

1. Open the project in Xcode
2. Select the **ShadowGuard** target
3. Go to **Signing & Capabilities**
4. Select your **Team** (Apple Developer Account)
5. Change the **Bundle Identifier** to something unique (e.g., `com.yourname.shadowguard`)
6. Repeat for the **ShadowGuardTunnel** target
   - Bundle ID must be: `<your-main-bundle-id>.tunnel`

### Step 3: Configure App Groups

1. In **Signing & Capabilities**, add **App Groups** capability
2. Create a new group: `group.com.yourname.shadowguard`
3. Update the group identifier in the code:
   - `ShadowGuard/Core/TunnelManager.swift`
   - `ShadowGuardTunnel/PacketTunnelProvider.swift`
   - `ShadowGuardDNSProxy/DNSProxyProvider.swift`

### Step 4: Build and Run

1. Connect your iPhone via USB
2. Select your device as the build target
3. Press **Cmd + R** to build and run
4. Trust the developer certificate on your device:
   - Go to **Settings → General → VPN & Device Management**
   - Tap your developer certificate and trust it

### Step 5: Install Root CA Certificate

1. Open ShadowGuard on your device
2. Go to **Settings** tab
3. Tap **Install Certificate**
4. Follow the wizard:
   - Generate the root CA
   - Install the configuration profile
   - Trust the certificate in Settings

#### Manual Certificate Trust

After installing the profile:
1. Go to **Settings → General → About → Certificate Trust Settings**
2. Enable **Full Trust** for "ShadowGuard Root CA"

### Step 6: Enable Protection

1. Return to ShadowGuard
2. Tap the **Power Button** on the Dashboard
3. Allow VPN configuration when prompted
4. You'll see a VPN icon in the status bar when active

> **Important**: The root CA certificate is required for MITM proxy to inspect HTTPS traffic and block dynamic ads.

## Usage

### Dashboard
- **Power Button**: Toggle protection on/off
- **Protection Ring**: Shows overall protection level
- **Stats Cards**: Blocked requests, data saved, active filters
- **Top Blocked**: Most frequently blocked domains

### Rules
- **Built-in Lists**: Toggle popular filter lists
- **Custom Rules**: Add your own blocking rules
- **Rule Types**:
  - **Block**: Prevent requests matching the pattern
  - **Allow**: Whitelist requests (overrides blocks)
  - **Redirect**: Redirect matching requests

### Rule Syntax Examples

```
# Block domain and all subdomains
||ads.example.com^

# Block specific URL pattern
||example.com/ads/*

# Block with regex
/tracking[0-9]+\.js/

# Whitelist a domain
@@||trusted-site.com^

# Block third-party requests
||tracker.com^$third-party
```

### Logs
- **Real-time**: See all traffic as it happens
- **Filter by Type**: Blocked, Allowed, TLS, Errors
- **Search**: Find specific domains or URLs
- **Export**: Share logs for debugging

### Settings
- **Certificate Management**: Install, export, or regenerate CA
- **Bypass Domains**: Add domains that skip MITM (for pinned apps)
- **DNS over HTTPS**: Enable encrypted DNS queries
- **Advanced Options**: Proxy port, log level, etc.

### Debug Console
- Shake your device to open the debug console
- Type `help` for available commands
- Useful for troubleshooting and advanced operations

## Architecture

```
ShadowGuard/
├── ShadowGuardApp.swift          # App entry point
├── ContentView.swift             # Main tab navigation
├── Core/
│   ├── AppState.swift            # Global state management
│   ├── TunnelManager.swift       # VPN tunnel lifecycle
│   ├── LogStore.swift            # Traffic logging
│   ├── FilterEngine.swift        # Rule parsing & matching
│   ├── DomainMatcher.swift       # Trie + Bloom filter matching
│   ├── SNIExtractor.swift        # TLS ClientHello parser
│   └── BlocklistManager.swift    # Blocklist updates
├── UI/
│   ├── Theme/
│   │   ├── Colors.swift          # Color palette
│   │   └── Styles.swift          # Custom view modifiers
│   ├── Components/
│   │   └── Components.swift      # Reusable UI components
│   └── Views/
│       ├── DashboardView.swift   # Home screen
│       ├── RulesView.swift       # Filter management
│       ├── LogsView.swift        # Traffic logs
│       ├── SettingsView.swift    # Configuration
│       └── BlocklistUpdateSheet.swift # Blocklist management
└── Resources/
    └── Blocklists/               # Bundled blocklists

ShadowGuardTunnel/
├── PacketTunnelProvider.swift    # Packet Tunnel with SNI inspection
├── Info.plist                    # Extension configuration
└── ShadowGuardTunnel.entitlements

ShadowGuardDNSProxy/
├── DNSProxyProvider.swift        # DNS-level blocking
├── Info.plist                    # Extension configuration
└── ShadowGuardDNSProxy.entitlements
```

## How It Works

1. **VPN Tunnel**: Creates a local VPN tunnel using `NEPacketTunnelProvider`
2. **MITM Proxy**: Routes HTTP/HTTPS traffic through local proxy on port 8899
3. **TLS Interception**: For HTTPS, the proxy:
   - Terminates the client's TLS connection using a generated certificate
   - Establishes a new TLS connection to the real server
   - Decrypts, inspects, and re-encrypts traffic
4. **DNS Blocking**: Additional layer - blocks ad domains at DNS level
5. **Filtering**: Requests are checked against filter rules before forwarding
6. **Blocking**: Matched requests receive a blocked response instead of forwarding

## Security Considerations

⚠️ **Important Security Information**

- **Personal Use Only**: Only use on devices you own
- **Root CA Trust**: Installing a root CA is a significant security decision
- **Traffic Visibility**: All decrypted traffic passes through the app
- **No External Servers**: All processing happens locally on-device
- **Certificate Pinning**: Some apps (banking, etc.) will not work through MITM - they are automatically bypassed

## Troubleshooting

### VPN Won't Connect
1. Check that the Network Extension entitlement is properly configured
2. Ensure all targets have matching App Group identifiers
3. Try removing and reinstalling the VPN configuration in Settings

### Ads Still Showing
1. Ensure the root CA certificate is installed and trusted
2. Update blocklists from the Dashboard
3. Some apps use certificate pinning and bypass MITM (add to bypass list)
4. Add custom rules for specific ad domains/URLs

### Certificate Not Trusted
1. Go to Settings → General → About → Certificate Trust Settings
2. Enable full trust for "ShadowGuard Root CA"
3. If not visible, reinstall the certificate profile from the app

### Apps Not Working
1. Some apps use certificate pinning and won't work through MITM
2. Add the app's domains to the bypass list in Settings
3. Common bypass domains are pre-configured (Apple, banking, etc.)

### High Battery Usage
1. Reduce log level in Settings
2. Disable cosmetic filtering if not needed
3. The VPN indicator itself doesn't indicate high usage

## Known Limitations

- **HTTP/3 (QUIC)**: Falls back to TCP; native QUIC interception not supported
- **Certificate Pinning**: Cannot intercept pinned connections (bypassed automatically)
- **Some System Traffic**: Certain iOS system traffic bypasses the tunnel
- **First-Party Ads**: Ads served from same domain as content are harder to block

## License

This project is for personal, educational use only. Not intended for commercial distribution.

## Disclaimer

This software performs man-in-the-middle interception of network traffic. Use responsibly and only on your own devices. The developers are not responsible for any misuse or damages arising from the use of this software.

---

**Built with ❤️ using Swift, SwiftUI, and NetworkExtension**
