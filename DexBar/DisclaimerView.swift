//  DisclaimerView.swift
//  DexBar

import SwiftUI

struct DisclaimerView: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    private struct Section {
        let symbol: String
        let title: String
        let body: String
    }

    private let sections: [Section] = [
        Section(
            symbol: "person.fill",
            title: "Personal use only",
            body: "Hobby project. Not affiliated with, endorsed by, or sponsored by Dexcom or Glooko. Non-commercial."
        ),
        Section(
            symbol: "exclamationmark.triangle.fill",
            title: "Unofficial & undocumented APIs",
            body: "Uses private/undocumented APIs that may change or disappear at any time. Continued use may violate Dexcom's and/or Glooko's Terms of Service."
        ),
        Section(
            symbol: "cross.circle.fill",
            title: "Not medical advice",
            body: "DexBar is not a medical device and is not approved for clinical use. Never make treatment or dosing decisions based on data shown here. Always rely on your approved CGM device and consult your healthcare provider."
        ),
        Section(
            symbol: "exclamationmark.shield.fill",
            title: "No warranties or guarantees",
            body: "Provided as-is with no warranty of any kind. Data may be inaccurate, delayed, or missing. You are solely responsible for any consequences of using this software."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Before You Continue")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            ForEach(sections, id: \.title) { section in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: section.symbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .fontWeight(.semibold)
                        Text(section.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Button("I do not accept — close the app", action: onDecline)
                Spacer()
                Button("I understand and accept", action: onAccept)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
