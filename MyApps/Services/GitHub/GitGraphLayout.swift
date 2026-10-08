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

    // Make room for all tracks while keeping the graph reasonably compact on iPhone.
    var laneSpacing: CGFloat {
        max(8, min(21, 140 / CGFloat(max(1, laneCount))))
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

            maxLanes = max(maxLanes, nodeLane + 1, next.count)
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

    private static func topologicalOrder(_ commits: [GitHubCommit]) -> [GitHubCommit] {
        let positions = Dictionary(
            uniqueKeysWithValues: commits.enumerated().map { ($0.element.sha, $0.offset) }
        )
        var pendingChildren = [Int](repeating: 0, count: commits.count)

        for commit in commits {
            for parent in commit.parents {
                if let parentIndex = positions[parent.sha] {
                    pendingChildren[parentIndex] += 1
                }
            }
        }

        var emitted = Set<Int>()
        var result: [GitHubCommit] = []
        result.reserveCapacity(commits.count)

        while result.count < commits.count {
            // Prefer the original API order among ready commits so unrelated
            // history does not jump around unnecessarily.
            guard let index = commits.indices.first(where: {
                !emitted.contains($0) && pendingChildren[$0] == 0
            }) else {
                // Git histories are acyclic; keep data visible if the remote
                // response is unexpectedly inconsistent.
                for index in commits.indices where !emitted.contains(index) {
                    result.append(commits[index])
                }
                break
            }

            emitted.insert(index)
            let commit = commits[index]
            result.append(commit)

            for parent in commit.parents {
                if let parentIndex = positions[parent.sha] {
                    pendingChildren[parentIndex] -= 1
                }
            }
        }

        return result
    }
}
