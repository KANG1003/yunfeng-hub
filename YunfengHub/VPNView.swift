//
//  VPNView.swift
//  WireGuard 连接界面
//

import SwiftUI

struct VPNView: View {
    @Environment(AppStore.self) private var store
    @State private var wg = WireGuardService()

    private var activeProfile: WGProfile? {
        store.profiles.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                VStack(alignment: .leading, spacing: 2) {
                    Text("WireGuard").font(.system(size: 27, weight: .bold))
                    Text("本地隧道 · \(activeProfile?.endpoint ?? "未配置")")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                connectRing
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)

                flowCards

                GlassCard {
                    VStack(spacing: 0) {
                        infoRow("配置", activeProfile?.name ?? "—")
                        Divider().opacity(0.3)
                        infoRow("Endpoint", activeProfile?.endpoint ?? "—", mono: true)
                        Divider().opacity(0.3)
                        infoRow("本机地址", activeProfile?.address ?? "—", mono: true)
                        Divider().opacity(0.3)
                        infoRow("Allowed IPs", activeProfile?.allowedIPs ?? "—", mono: true)
                        Divider().opacity(0.3)
                        infoRow("MTU", "\(activeProfile?.mtu ?? 1400)", mono: true)
                    }
                }

                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("导入配置").font(.system(size: 13.5, weight: .semibold))
                            Text("支持 .conf 文件，解析后加入列表")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        GhostButton(title: "导入", systemImage: "square.and.arrow.down") {
                            // 生产版：fileImporter 选 .conf → WireGuardService.parse
                        }
                    }
                }

                Text("真隧道需 NetworkExtension + WireGuardKit，并在开发者后台开启 VPN 能力；当前为界面演示。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
    }

    private var connectRing: some View {
        Button {
            wg.toggle(profile: activeProfile)
        } label: {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [ringColor.opacity(0.34), ringColor.opacity(0.04), .clear],
                        center: .center, startRadius: 2, endRadius: 92))
                    .overlay(Circle().strokeBorder(ringColor.opacity(0.55), lineWidth: 2))

                VStack(spacing: 2) {
                    Image(systemName: "power")
                        .font(.system(size: 33, weight: .light))
                    Text(wg.status.rawValue)
                        .font(.system(size: 12, weight: .medium)).tracking(2)
                        .foregroundStyle(wg.isOn ? Color.green : Color.secondary)
                    Text(wg.uptimeText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 178, height: 178)
            .shadow(color: wg.isOn ? .green.opacity(0.25) : .clear, radius: 26)
        }
        .buttonStyle(.plain)
    }

    private var ringColor: Color { wg.isOn ? .green : Color(hex: 0x4D8DFF) }

    private var flowCards: some View {
        HStack(spacing: 10) {
            statCard("下行", String(format: "%.1f", wg.downlink), "Mb/s")
            statCard("上行", String(format: "%.1f", wg.uplink), "Mb/s")
        }
    }

    private func statCard(_ label: String, _ value: String, _ unit: String) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 21, weight: .semibold))
                Text(unit).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func infoRow(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack {
            Text(k).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer()
            Text(v)
                .font(.system(size: mono ? 12 : 13, design: mono ? .monospaced : .default))
                .lineLimit(1)
        }
        .padding(.vertical, 8)
    }
}
