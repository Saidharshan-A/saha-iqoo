# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users

Frontline health workers and hackathon judges using an iQOO Android phone. The immediate task is a short, visible demonstration of phone-based vital-sign screening.

## Product Purpose

SAHA is an offline-first health screening system. SAHA TRACK PLUS is a separate focused APK that estimates a resting chest heartbeat rate from the phone's motion sensors and a fingertip pulse rate from the rear camera and flash, then presents both readings clearly.

## Positioning

The prototype turns hardware already present in the supplied phone into two visible, on-device screening experiences without requiring a wearable or network connection.

## Operating Context

The app is demonstrated on a connected iQOO I2501 at the iQOO Hackathon. A chest reading is taken while the user lies or sits still with the phone flat against the lower sternum. A pulse reading is taken with a fingertip covering the rear camera and flash.

## Capabilities and Constraints

- The two readings are acquired separately and shown separately.
- Chest heartbeat is an experimental seismocardiography-style estimate from accelerometer and gyroscope signals.
- Fingertip pulse is an optical photoplethysmography-style estimate from camera brightness changes under the flash.
- Measurements run locally on the phone.
- Results are screening estimates, not ECG, blood pressure, oxygen saturation, or a medical diagnosis.
- The existing SAHA APK and its features must remain intact.

## Brand Commitments

Use the name SAHA TRACK PLUS. Preserve SAHA's recognizable startup motion and India-first identity while making the focused measurement flow fast and easy for judges to understand.

## Evidence on Hand

- Existing SAHA splash implementation: `lib/app/splash_screen.dart`.
- Connected device: iQOO I2501 with accelerometer, gyroscope, rear camera, and adjustable torch.
- No dedicated heart-rate sensor was detected on the device.

## Product Principles

- Make the live sensor action visible.
- Never substitute a fabricated reading for a weak signal.
- Explain placement and recovery in one glance.
- Keep the demo fully on-device and usable without internet.
- Distinguish an experimental estimate from a clinical measurement.

## Accessibility & Inclusion

Use large touch targets, high-contrast labels, plain instructions, icons paired with text, and states that do not depend on color alone.
