import SwiftUI

/// 课程详情弹层（对应 course_detail_sheet.dart）
struct CourseDetailSheet: View {
    let course: Course
    let config: ScheduleConfig
    let onClose: () -> Void
    let onEdit: (Course) -> Void
    let onDelete: (String) -> Void

    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(course.name)
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                Button {
                    onEdit(course)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                infoRow(icon: "calendar", tint: .teal, text: weekText)
                Divider().padding(.leading, 46)
                infoRow(icon: "clock", tint: .orange, text: sectionTimeText)
                if !course.teacher.isEmpty {
                    Divider().padding(.leading, 46)
                    infoRow(icon: "person", tint: .blue, text: course.teacher)
                }
                if !course.location.isEmpty {
                    Divider().padding(.leading, 46)
                    infoRow(icon: "mappin.and.ellipse", tint: .red, text: course.location)
                }
            }
            .padding(.vertical, 4)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .confirmationDialog("删除这门课？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                onDelete(course.id)
            }
        }
    }

    private var weekText: String {
        let base = course.startWeek == course.endWeek
            ? "第 \(course.startWeek) 周"
            : "\(course.startWeek)-\(course.endWeek) 周"
        switch course.weekType {
        case .every: return base
        case .odd: return base + " · 单周"
        case .even: return base + " · 双周"
        }
    }

    private var sectionTimeText: String {
        var text = "第 \(course.startSection)-\(course.endSection) 节"
        if course.startSection <= config.timeSlots.count,
           course.endSection <= config.timeSlots.count {
            let start = config.timeSlots[course.startSection - 1]
            let end = config.timeSlots[course.endSection - 1]
            text += "   \(start.format(true)) - \(end.format(false))"
        }
        return text
    }

    private func infoRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
    }
}
