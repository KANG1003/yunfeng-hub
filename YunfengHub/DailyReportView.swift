//
//  DailyReportView.swift
//  日报：手写任务 + 模板生成 + 自动汇总
//

import SwiftUI
import UIKit

struct DailyReportView: View {
    @Environment(AppStore.self) private var store
    @State private var draft: String = ""
    @State private var output: String = ""
    @State private var showCopied = false

    private var doneCount: Int { store.tasks.filter(\.done).count }
    private var todoCount: Int { store.tasks.filter { !$0.done }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                VStack(alignment: .leading, spacing: 2) {
                    Text("日报").font(.system(size: 27, weight: .bold))
                    Text("\(Date.now.formatted(.dateTime.month().day())) · 待办 \(todoCount) 项")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(.top, 4)

                // 任务清单
                GlassCard {
                    SectionTitle(text: "今日任务", trailing: AnyView(
                        GhostButton(title: "添加", systemImage: "plus") { addTask() }
                    ))

                    VStack(spacing: 0) {
                        ForEach(store.tasks) { task in
                            taskRow(task)
                            Divider().opacity(0.25)
                        }
                    }
                }

                // 模板 + 生成
                GlassCard {
                    Text("模板").font(.system(size: 12)).foregroundStyle(.secondary)
                        .padding(.bottom, 8)

                    HStack(spacing: 8) {
                        ForEach(ReportTemplate.allCases) { t in
                            Chip(title: t.rawValue, selected: store.template == t) {
                                store.template = t
                                store.save()
                            }
                        }
                    }

                    PrimaryButton(title: "生成日报", systemImage: "wand.and.stars") {
                        output = ReportEngine.render(tasks: store.tasks,
                                                     template: store.template, date: .now)
                    }
                    .padding(.top, 12)

                    TextEditor(text: $output)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 170)
                        .padding(10)
                        .background(Color.white.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                        .padding(.top, 10)

                    HStack(spacing: 8) {
                        GhostButton(title: showCopied ? "已复制" : "复制",
                                    systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = output
                            showCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { showCopied = false }
                        }
                        GhostButton(title: "存档", systemImage: "tray.and.arrow.down") {
                            store.archiveToday()
                        }
                    }
                    .padding(.top, 10)
                }

                // 历史
                if !store.entries.isEmpty {
                    GlassCard {
                        SectionTitle(text: "历史记录")
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.entries.suffix(3).reversed()) { e in
                                HStack {
                                    Text(e.date, format: .dateTime.month().day().hour().minute())
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("完成 \(e.tasks.filter(\.done).count) 项")
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if output.isEmpty {
                output = ReportEngine.render(tasks: store.tasks,
                                             template: store.template, date: .now)
            }
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(spacing: 11) {
            Button { store.toggle(task) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(task.done ? Color.green : Color.white.opacity(0.32), lineWidth: 1.5)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(task.done ? Color.green : .clear))
                        .frame(width: 22, height: 22)
                    if task.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black.opacity(0.65))
                    }
                }
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 13.5))
                .strikethrough(task.done)
                .foregroundStyle(task.done ? Color.secondary : Color.primary)

            Spacer()

            Text(task.tag)
                .font(.system(size: 11))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.blue.opacity(0.18), in: Capsule())
                .foregroundStyle(Color(hex: 0xA8C6FF))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.deleteTask(task)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func addTask() {
        // 简版：用系统弹窗输入；生产版可换成自定义 sheet
        let alert = UIAlertController(title: "新增任务", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "任务内容" }
        alert.addTextField { $0.placeholder = "标签（运维/开发…）" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let t = alert.textFields?.first?.text ?? ""
            guard !t.isEmpty else { return }
            let tag = alert.textFields?.last?.text ?? "其他"
            store.addTask(title: t, tag: tag.isEmpty ? "其他" : tag)
        })
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(alert, animated: true)
        }
    }
}
