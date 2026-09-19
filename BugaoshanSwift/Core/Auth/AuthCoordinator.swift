import Foundation

/// L2 调度器（对应 lib/services/auth/auth_coordinator.dart）：
/// 拓扑并发预热（依赖先就绪）、失败隔离（单模块失败不阻塞其他模块）、
/// 环检测、warmUpAll single-flight。预热失败不永久禁用模块（业务仍可按需认证）。
actor AuthCoordinator {

    private let modules: [any SubsystemAuth]
    private let log: AuthLogger

    private var warmUpTask: Task<Void, Never>?
    private var warmUpToken: UUID?

    init(modules: [any SubsystemAuth], log: AuthLogger = .shared) {
        self.modules = modules
        self.log = log
    }

    /// 后台预热全部模块；并发调用共享一次执行
    func warmUpAll() async {
        if warmUpTask != nil { return }
        let task = Task<Void, Never> {
            await self.doWarmUpAll()
        }
        let token = UUID()
        warmUpTask = task
        warmUpToken = token
        defer {
            if warmUpToken == token {
                warmUpTask = nil
                warmUpToken = nil
            }
        }
        await task.value
    }

    /// 登录后 fire-and-forget 预热
    nonisolated func warmUpAllInBackground() {
        Task {
            await self.warmUpAll()
        }
    }

    private func doWarmUpAll() async {
        log.i("AuthCoordinator", "warmUpAll: start (\(modules.count) modules)")

        // 模块级任务记忆（线程安全容器；任务体内会再读它）
        final class TaskMap: @unchecked Sendable {
            private let lock = NSLock()
            private var map: [ObjectIdentifier: Task<Bool, Never>] = [:]
            func task(for id: ObjectIdentifier, make: () -> Task<Bool, Never>) -> Task<Bool, Never> {
                lock.lock(); defer { lock.unlock() }
                if let existing = map[id] { return existing }
                let task = make()
                map[id] = task
                return task
            }
        }

        let memo = TaskMap()

        func ensure(_ auth: any SubsystemAuth, path: Set<ObjectIdentifier>) -> Task<Bool, Never> {
            let id = ObjectIdentifier(auth)
            return memo.task(for: id) {
                Task<Bool, Never> {
                    // 先保证依赖（并发等待；环 → 跳过该依赖并告警）
                    for dep in auth.dependencies {
                        let depId = ObjectIdentifier(dep)
                        if path.contains(depId) {
                            log.w("AuthCoordinator", "cycle detected at \(dep.moduleId), skipping")
                            continue
                        }
                        _ = await ensure(dep, path: path.union([id])).value
                    }
                    do {
                        try await auth.ensureAuthenticated()
                        return true
                    } catch {
                        log.w("AuthCoordinator", "warm-up \(auth.moduleId) failed: \(error)")
                        return false
                    }
                }
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for module in modules {
                let task = ensure(module, path: [])
                group.addTask {
                    _ = await task.value
                }
            }
        }
        log.i("AuthCoordinator", "warmUpAll: done")
    }

    /// 全部失效（登出时调用）
    func invalidateAll() async {
        warmUpTask = nil
        warmUpToken = nil
        for module in modules {
            await module.invalidate()
        }
        log.i("AuthCoordinator", "invalidateAll: done")
    }
}
