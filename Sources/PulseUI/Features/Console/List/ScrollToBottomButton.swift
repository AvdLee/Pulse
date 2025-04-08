//
//  ScrollToBottomButton.swift
//  Pulse
//
//  Created by A.J. van der Lee on 08/04/2025.
//

import SwiftUI

struct ScrollToBottomButton: View {
    let proxy: ScrollViewProxy
    let bottomID: Namespace.ID

    @SceneStorage("com-rocketsim-connect-is-now-enabled") private var isNowEnabled = true

    var body: some View {
        ZStack {
            if !isNowEnabled {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation {
                                proxy.scrollTo(bottomID, anchor: .bottom)
                            }
                        }) {
                            Text("Scroll to bottom")
                        }
                        .rocketSimConnectButtonStyle(size: .small)
                        Spacer()
                    }
                    .padding(.bottom)
                }
                .transition(.move(edge: .bottom))
                .animation(.easeInOut, value: isNowEnabled)
            }
        }
    }
}

struct RocketSimConnectButtonStyle: ButtonStyle {
    enum Size {
        case small, medium

        var fontSize: CGFloat {
            switch self {
            case .small: return 10
            case .medium: return 12
            }
        }
        var cornerRadius: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 8
            }
        }
        var insets: EdgeInsets {
            switch self {
            case .small:
                return .init(top: 4, leading: 8, bottom: 4, trailing: 8)
            case .medium:
                return .init(top: 8, leading: 12, bottom: 8, trailing: 12)
            }
        }
    }

    var size: Size
    var insets: EdgeInsets?
    var backgroundColor: Color
    
    init(size: Size = .small, insets: EdgeInsets? = nil, backgroundColor: Color? = nil) {
        self.size = size
        self.insets = insets
        self.backgroundColor = backgroundColor ?? .black.opacity(0.45)
    }
    
    struct RoundedButton: View {
        let configuration: ButtonStyle.Configuration
        let size: RocketSimConnectButtonStyle.Size
        let insets: EdgeInsets?
        var backgroundColor: Color = .black
        @Environment(\.isEnabled) private var isEnabled: Bool

        var body: some View {
            configuration
                .label
                .font(.system(size: size.fontSize))
                .padding(insets ?? size.insets)
                .foregroundColor(Color.white.opacity(isEnabled ? 1.0 : 0.4))
                .background(backgroundColor)
                .cornerRadius(size.cornerRadius)
                .opacity(configuration.isPressed ? 0.6 : 1.0)
        }
    }

    func makeBody(configuration: ButtonStyle.Configuration) -> some View {
        RoundedButton(configuration: configuration, size: size, insets: insets, backgroundColor: backgroundColor)
    }
}

extension View {
    func rocketSimConnectButtonStyle(size: RocketSimConnectButtonStyle.Size = .small, insets: EdgeInsets? = nil, backgroundColor: Color? = nil) -> some View {
        self.buttonStyle(RocketSimConnectButtonStyle(size: size, insets: insets, backgroundColor: backgroundColor))
    }
}
