# Acknowledgements

Oven is built on the shoulders of great open-source work.

---

## App Icon

| Name | Author | License |
|---|---|---|
| [Oven icon](https://www.flaticon.com/free-icons/oven) | Flaticon | Flaticon License |

Free for personal and commercial use with attribution.

---

## Runtime Tools

These tools are downloaded and managed by Oven at runtime. Each is subject to its own license.

### [tart](https://github.com/cirruslabs/tart)

**Author:** Cirrus Labs  
**License:** Fair Source License v0.9 ⚠️

Virtualization tool for running macOS and Linux VMs on Apple Silicon. Oven uses Tart as its VM hypervisor for all create, clone, run, stop, suspend, push, and pull operations.

> The Fair Source License v0.9 is not an OSI-approved open-source license and has commercial use restrictions. Review the license before using Tart in a commercial context.

---

### [packer](https://github.com/hashicorp/packer)

**Author:** HashiCorp / IBM  
**License:** Business Source License 1.1 ⚠️

Tool for building automated machine images. Oven uses Packer to orchestrate base VM builds from HCL templates.

> The Business Source License 1.1 is not an OSI-approved open-source license and has commercial use restrictions. Review the license before using Packer in a commercial context.

---

### [packer-plugin-tart](https://github.com/cirruslabs/packer-plugin-tart)

**Author:** Cirrus Labs  
**License:** Mozilla Public License 2.0

Packer plugin that adds support for Tart VMs. Oven downloads and installs this plugin automatically via `packer init`.

---

### [mist-cli](https://github.com/ninxsoft/mist-cli)

**Author:** Nindi Gill  
**License:** MIT License

Command-line tool to download macOS Firmwares and Installers. Used by Oven as an alternative firmware source when the ipsw.me API is unavailable or when you need access to beta firmware.

---

### [jq](https://github.com/jqlang/jq)

**Author:** Stephen Dolan and contributors  
**License:** MIT License

Lightweight and flexible command-line JSON processor. Used internally by Oven to parse structured output from Packer and other tools during build pipelines.

---

### [ipsw.me](https://ipsw.me/)

IPSW information lookup API. Oven queries this service to discover available macOS firmware download URLs for `VirtualMac2,1` (the Tart virtual hardware identifier).

---

## Other Tools & Services

### [GitHub](https://github.com/)

GitHub, the GitHub logo, and the Octocat are trademarks of GitHub, Inc., registered in the U.S. and other countries. Oven integrates with GitHub for dependency version checking, CirrusLabs template fetching, and GitHub Container Registry (GHCR) image operations.

---

### [Docker](https://docker.com/)

Docker® is a trademark or registered trademark of Docker, Inc. in the United States and/or other countries. Oven supports Docker Hub as an OCI-compatible registry target for pushing and pulling base VM images.

---

### AI-usage

This project was built with assistance of AI tools. It has been tested as thoroughly as possible, but that was in the context of my workflow, which may differ with yours. There may be use-cases where it fails.

---

## Trademarks

### [Apple](https://apple.com/)

This project is not endorsed in any way shape or form by Apple. Apple, iPhone, iPad, Mac, and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions.

Cropped versions of macOS built-in wallpapers are included just for VM reference.

## Inspiration

### [Motionbug](https://github.com/motionbug)

[Rob's](https://motionbug.com) great work experimenting building VMs with Tart are what led me to get into this whole journey automating and improving my own workflows with Tart and VMs.

I most certainly looked up to ["The Tart Factory"](https://github.com/motionbug/detaartenfabriek) for inspiration for how to surface Tart's functions and pulling images from CirrusLabs' image templates.

---

### [UTM](https://github.com/utmapp/UTM)

I continously tested UTM to learn and improve Oven's UI and UX.

---

### [VirtualBuddy](https://github.com/insidegui/VirtualBuddy)

I tested a lot building VMs with VirtualBuddy to figure out a good workflow for building Base VMs and working VMs in Oven.
