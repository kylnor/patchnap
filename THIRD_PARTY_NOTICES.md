# Third-party software

Patchnap's own code and authored vector mascot are MIT licensed.

The release bundle may include the `mas` command-line executable from https://github.com/mas-cli/mas, Copyright (c) 2015 Andrew Naylor, Ross Goldberg and mas-cli contributors, under the MIT license. Its bundled version is recorded in Contents/Resources/mas.version. Its license grants permission to use, copy, modify, merge, publish, distribute, sublicense and sell copies, subject to inclusion of the copyright and permission notice. THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY ARISING FROM THE SOFTWARE OR ITS USE.

The complete upstream license and dependency notices must be included beside the binary as mas-LICENSE and mas-NOTICES when packaging a release. Source build scripts locate mas locally; they do not download or execute a remote installer. Homebrew is an optional external runtime integration and is not bundled with Patchnap.

The mas 7.0.0 distribution includes pinned Swift dependencies. Full upstream license texts, available NOTICE files, and revision/source provenance are included under Resources/ThirdParty/mas-7.0.0 and copied into release bundles. This includes BigInt, Chronometer, Gram, Hitch, Sextant, Spanker, Swift Argument Parser, Swift Atomics, Swift Collections, swift-json and SwiftSoup.
