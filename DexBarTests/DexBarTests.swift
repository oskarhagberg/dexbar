import Testing
@testable import DexBar

// Tests are organised into focused suites:
//   DexcomReadingTests   – JSON decoding and mg/dL → mmol/L conversion
//   GlucoseFormatterTests – trend arrows, low-glucose threshold, status labels
//   DexcomClientTests    – HTTP request construction and response decoding
