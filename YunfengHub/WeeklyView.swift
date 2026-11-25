//
//  WeeklyView.swift
//  weekiy：周视图 + 完成率 + 周报生成
//

import SwiftUI
import UIKit

struct WeeklyView: View {
    @Environment(AppStore.self) private var store
    @State private var output: String = ""
    @State private var selectedDay: Int = 0

    private var stats: [DayStat] { WeeklyEngine.stats() }
    private var rate: Double { WeeklyEngine.completionRate(stats) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                VStack(alignment: .leading, spacing: 2) {
                    Text("weekiy").font(.system(size: 27, weight: .bold))
                    Text(weekRangeText).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                weekStrip

                GlassCard {
                    HStack {
                        Text("本周完成率").font(.system(size: 13.5, weight: .semibold))
                        Spacer()
                        Text("\(Int(rate * 100))%")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.green)
                    }
                    .padding(.bottom, 14)

                    VStack(spacing: 9) {
                        barLine("完成", rate)
                        barLine("计划", min(1.0, rate + 0.12))
                        barLine("延期", max(0, 1 - rate - 0.08), tint: Color.orange)
                    }
                }

                GlassCard {
                    SectionTitle(text: "周报生成", trailing: AnyView(
                        PrimaryButton(title: "生成") {
                            output = WeeklyEngine.weeklyReport(stats: stats, entries: store.entries)
                        }
                        .frame(width: 86)
                    ))

                    TextEditor(text: $output)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 200)
                        .padding(10)
                        .background(Color.white.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                        .padding(.top, 10)

                    GhostButton(title: "复制周报", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = output
                    }
                    .padding(.top, 10)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if output.isEmpty {
                output = WeeklyEngine.weeklyReport(stats: stats, entries: store.entries)
            }
        }
    }

    private var weekRangeText: String {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: .now) else { return "本周" }
        let f = DateFormatter(); f.dateFormat = "MM/dd"
        let end = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let week = cal.component(.weekOfYear, from: .now)
        return "第 \(week) 周 · \(f.string(from: interval.start)) – \(f.string(from: end))"
    }

    private var weekStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { idx, d in
                Button { selectedDay = idx } label: {
                    VStack(spacing: 4) {
                        Text(d.label).font(.system(size: 12))
                        Text("\(d.date)").font(.system(size: 15, weight: .semibold))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.18))
                                Capsule().fill(Color.green)
                                    .frame(width: geo.size.width * d.rate)
                            }
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 8)
                    }
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selectedDay == idx ? Color.blue.opacity(0.22) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selectedDay == idx ? Color.blue.opacity(0.5)
                                                             : Color.white.opacity(0.14), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func barLine(_ label: String, _ value: Double, tint: Color = Color(hex: 0x4D8DFF)) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [tint, Color.green],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * value)
                }
            }
            .frame(height: 8)
            Text("\(Int(value * 100))%")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}
