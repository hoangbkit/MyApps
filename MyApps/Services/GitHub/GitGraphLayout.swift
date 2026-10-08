import Foundation
import CoreGraphics

/// All connections are derived from actual commit parent SHAs, not a merge flag.
struct GitGraphRowLayout: Equatable {
    let nodeLane: Int
    let incomingLanes: [Int]
    let continuingLanes: [Int]
    let outgoingLanes: [Int]
    let isMerge: Bool
}

struct GitGraphSnapshot {
    let commits: [GitHubCommit]
    let rows: [GitGraphRowLayout]
    let laneCount: Int

    // Large repositories can have many branch heads. Never let a very
    // wide graph eat the title column on a narrow iPhone.
    var laneSpacing: CGFloat {
        min(20, 104 / CGFloat(max(1, laneCount - 1)))
    }

    var width: CGFloat {
        24 + CGFloat(max(0, laneCount - 1)) * laneSpacing
    }
}

enum GitGraphLayout {
    static func make(_ commits: [GitHubCommit]) -> GitGraphSnapshot {
        // A parent must follow its child. The GitHub REST commits endpoint is
        // generally in that order, but author-date ordering is not guaranteed
        // to be topological for every history.
        let ordered = topologicalOrder(commits)
        var active: [String?] = []
        var rows: [GitGraphRowLayout] = []
        var maxLanes = 1

        for commit in ordered {
            let incoming = active.indices.filter { active[$0] == commit.sha }
            let nodeLane = incoming.first
                ?? active.firstIndex(where: { $0 == nil })
                ?? active.count

            if nodeLane == active.count {
                active.append(nil)
            }

            // Tracks for other commits continue straight through this row.
            let continuing = active.indices.filter {
                active[$0] != nil && !incoming.contains($0)
            }

            var next = active
            for lane in incoming {
                next[lane] = nil
            }

            var outgoing: [Int] = []
            for (index, parent) in commit.parents.enumerated() {
                // Reuse an existing track when multiple children share a parent.
                if let existing = next.firstIndex(where: { $0 == parent.sha }) {
                    outgoing.append(existing)
                    continue
                }

                let lane: Int
                if index == 0 && next[nodeLane] == nil {
                    // First parent stays on the commit's current track.
                    lane = nodeLane
                } else {
                    // Additional parents diverge to the right, without moving
                    // the already active tracks.
                    lane = next.indices.first(where: {
                        $0 > nodeLane && next[$0] == nil
                    }) ?? next.count
                }

                if lane == next.count {
                    next.append(nil)
                }
                next[lane] = parent.sha
                outgoing.append(lane)
            }

            maxLanes = max(max(maxLanes, nodeLane + 1), next.count)
            rows.append(
                GitGraphRowLayout(
                    nodeLane: nodeLane,
                    incomingLanes: incoming,
                    continuingLanes: continuing,
                    outgoingLanes: outgoing,
                    isMerge: commit.isMerge
                )
            )
            active = next
        }

        return GitGraphSnapshot(
            commits: ordered,
            rows: rows,
            laneCount: maxLanes
        )
    }

    // Topological sort with an index min-heap: O((commits + parents) log commits).
    // Prefer the original API position whenever multiple commits are ready.
    private static func topologicalOrder(_ commits: [GitHubCommit]) -> [GitHubCommit] {
        let positions = Dictionary(
            uniqueKeysWithValues: commits.enumerated().map { ($0.element.sha, $0.offset) }
        )
        var remainingChildren = [Int](repeating: 0, count: commits.count)

        for commit in commits {
            for parent in commit.parents {
                if let parentIndex = positions[parent.sha] {
                    remainingChildren[parentIndex] += 1
                }
            }
        }

        var ready = IndexMinHeap()
        for index in commits.indices where remainingChildren[index] == 0 {
            ready.insert(index)
        }

        var emitted = [Bool](repeating: false, count: commits.count)
        var result: [GitHubCommit] = []
        result.reserveCapacity(commits.count)

        while let index = ready.popMin() {
            emitted[index] = true
            let commit = commits[index]
            result.append(commit)
            for parent in commit.parents {
                if let parentIndex = positions[parent.sha] {
                    remainingChildren[parentIndex] -= 1
                    if remainingChildren[parentIndex] == 0 {
                        ready.insert(parentIndex)
                    }
                }
            }
        }

        // Git commits cannot have a cycle, but retain everything if an
        // unexpectedly inconsistent API response prevents complete sorting.
        if result.count < commits.count {
            for index in commits.indices where !emitted[index] {
                result.append(commits[index])
            }
        }
        return result
    }

    private struct IndexMinHeap {
        private var values: [Int] = []

        mutating func insert(_ element: Int) {
            values.append(element)
            var index = values.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                if values[parent] <= values[index] { break }
                values.swapAt(parent, index)
                index = parent
            }
        }

        mutating func popMin() -> Int? {
            guard !values.isEmpty else { return nil }
            if values.count == 1 { return values.removeLast() }
            let minimum = values[0]
            values[0] = values.removeLast()

            var index = 0
            while true {
                let left = index * 2 + 1
                guard left < values.count else { break }
                let right = left + 1
                let child = right < values.count && values[right] < values[left]
                    ? right : left
                if values[index] <= values[child] { break }
                values.swapAt(index, child)
                index = child
            }
            return minimum
        }
    }

}
