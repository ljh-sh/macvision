# Security Policy

## Supported Versions

Only the latest release receives security updates.

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |
| older   | :x:                |

## Reporting a Vulnerability

Please report security vulnerabilities privately by emailing [lijunhao@x-cmd.com](mailto:lijunhao@x-cmd.com).

Do not open a public issue for security problems. We will respond as quickly as possible and coordinate a fix and disclosure.

## Privacy

macvision processes images locally with Apple's `Vision` framework. It does not upload images or make network requests on your behalf. The `--screen` option shells out to the macOS `screencapture` tool, which itself may require Screen Recording permission in System Settings.
