import SwiftUI
import Foundation

// Resolve the property wrapper explicitly: newer SDKs also export a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Palette {
    static let background = Color(red: 0.97, green: 0.95, blue: 0.90)
    static let ink = Color(red: 0.18, green: 0.22, blue: 0.18)
    static let muted = Color(red: 0.44, green: 0.47, blue: 0.41)
    static let orange = Color(red: 0.91, green: 0.39, blue: 0.19)
    static let sage = Color(red: 0.83, green: 0.88, blue: 0.75)
}

struct ThemeBackground: View {
    var body: some View { Palette.background }
}

struct PupView: View {
    var awake: Bool
    var celebrate: Bool
    var animate: Bool
    @ViewState<Bool> private var bob = false
    var body: some View {
        ZStack {
            Ellipse().fill(Palette.ink.opacity(0.08)).frame(width: 90, height: 12).offset(y: 53)
            Circle().fill(Palette.sage.opacity(0.6)).frame(width: 105, height: 105).offset(y: 0)
            Group {
                Capsule().fill(Palette.orange).frame(width: 17, height: 44).rotationEffect(.degrees(celebrate ? 55 : -25)).offset(x: 37, y: 27)
                RoundedRectangle(cornerRadius: 25).fill(Color(red: 0.76, green: 0.49, blue: 0.28)).frame(width: 64, height: 65).offset(y: 24)
                Capsule().fill(Palette.orange).frame(width: 29, height: 58).rotationEffect(.degrees(18)).offset(x: -33, y: -16)
                Capsule().fill(Palette.orange).frame(width: 29, height: 58).rotationEffect(.degrees(-18)).offset(x: 33, y: -16)
                RoundedRectangle(cornerRadius: 28).fill(Color(red: 0.93, green: 0.69, blue: 0.40)).frame(width: 73, height: 65).offset(y: -10)
                Ellipse().fill(Palette.background).frame(width: 44, height: 31).offset(y: 4)
                if awake {
                    HStack(spacing: 22) {
                        Capsule().fill(Palette.ink).frame(width: 5, height: celebrate ? 4 : 9)
                        Capsule().fill(Palette.ink).frame(width: 5, height: celebrate ? 4 : 9)
                    }.offset(y: -17)
                } else {
                    HStack(spacing: 18) { Text("⌣"); Text("⌣") }.font(.system(size: 18, weight: .bold)).offset(y: -18)
                }
                Ellipse().fill(Palette.ink).frame(width: 12, height: 8).offset(y: -1)
                Text("ᴗ").font(.system(size: 23, weight: .bold)).foregroundStyle(Palette.ink).offset(y: 9)
                Capsule().fill(Palette.ink).frame(width: 48, height: 8).offset(y: 24)
                Circle().fill(Palette.orange).frame(width: 11, height: 11).overlay(Image(systemName: "pawprint.fill").font(.system(size: 6)).foregroundStyle(.white)).offset(y: 31)
                HStack(spacing: 24) {
                    Capsule().fill(Color(red: 0.93, green: 0.69, blue: 0.40)).frame(width: 19, height: 22)
                    Capsule().fill(Color(red: 0.93, green: 0.69, blue: 0.40)).frame(width: 19, height: 22)
                }.offset(y: 48)
            }.offset(y: bob && animate && awake ? -3 : 0)
                .rotationEffect(.degrees(celebrate && animate ? -5 : 0))
            if !awake { Text("z z").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Palette.muted).rotationEffect(.degrees(-12)).offset(x: 37, y: -43) }
            if celebrate { Image(systemName: "sparkles").foregroundStyle(Palette.orange).offset(x: -48, y: -43) }
        }
        .onAppear { if animate { withAnimation(.easeInOut(duration: 0.45).repeatCount(2, autoreverses: true)) { bob = true } } }
        .animation(animate ? .spring(duration: 0.35) : nil, value: celebrate)
    }
}
