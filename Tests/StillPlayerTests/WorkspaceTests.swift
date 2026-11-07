import XCTest
import PlayerCore
@testable import StillPlayer

@MainActor final class WorkspaceTests: XCTestCase {
    private var model: AppModel!
    private var workspace: Workspace!

    override func setUp() async throws {
        model = AppModel()
        model.selectedID = "demo-focus"
        model.pinned = ["demo-focus", "demo-evening"]
        workspace = Workspace()
        workspace.model = model
    }

    func testTypingFiltersTheOpenPlaylistInPlace() {
        XCTAssertEqual(workspace.rows().count, 12)
        workspace.filterText = "frank"
        XCTAssertEqual(workspace.rows().map(\.track.title), ["Pink + White", "Nights"])
        XCTAssertEqual(workspace.rows().map(\.number), [11, 12], "Rows keep their playlist position")
        XCTAssertEqual(workspace.filters["playlist:demo-focus"], "frank")
    }

    func testSortingTogglesDirectionAndNumberRestoresPlaylistOrder() {
        workspace.toggleSort(.duration)
        XCTAssertEqual(workspace.rows().first?.track.title, "Intro")
        workspace.toggleSort(.duration)
        XCTAssertEqual(workspace.rows().first?.track.title, "Weightless")
        workspace.toggleSort(.number)
        XCTAssertEqual(workspace.rows().first?.number, 1)
    }

    func testMusicAppModeHasNoQueue() {
        XCTAssertTrue(workspace.queueSupported)
        workspace.debugMusicAppLayout = true
        XCTAssertFalse(workspace.queueSupported)
    }

    func testEscapeInTheFilterClearsThenHides() {
        workspace.revealFilter()
        XCTAssertTrue(workspace.filterVisible)
        workspace.filterText = "nights"
        workspace.escapeFilter()
        XCTAssertEqual(workspace.filterText, "")
        XCTAssertTrue(workspace.filterVisible)
        workspace.escapeFilter()
        XCTAssertFalse(workspace.filterVisible)
    }

    func testClickCommandClickAndShiftClickSelectLikeFinder() {
        let rows = workspace.rows()
        workspace.click(row: rows[1], command: false, shift: false)
        XCTAssertEqual(workspace.selection, [rows[1].id])
        workspace.click(row: rows[4], command: false, shift: true)
        XCTAssertEqual(workspace.selection, Set(rows[1...4].map(\.id)))
        workspace.click(row: rows[2], command: true, shift: false)
        XCTAssertEqual(workspace.selection, Set([rows[1], rows[3], rows[4]].map(\.id)))
        workspace.selectAll()
        XCTAssertEqual(workspace.selection.count, rows.count)
    }

    func testArrowKeysMoveAndExtendTheSelection() {
        workspace.filterText = "o"
        let rows = workspace.rows()
        workspace.moveSelection(1)
        XCTAssertEqual(workspace.selection, [rows[0].id])
        workspace.moveSelection(1)
        XCTAssertEqual(workspace.selection, [rows[1].id])
        workspace.moveSelection(1, extend: true)
        XCTAssertEqual(workspace.selection, [rows[1].id, rows[2].id])
        workspace.moveSelection(-1)
        XCTAssertEqual(workspace.selection, [rows[0].id])
        XCTAssertEqual(workspace.scrollRequest, rows[0].id)
    }

    func testSelectionIsRememberedPerPlaylist() async throws {
        workspace.moveSelection(1)
        let first = workspace.selection
        workspace.select("demo-drive")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.selectedID, "demo-drive")
        XCTAssertTrue(workspace.selection.isEmpty)
        workspace.select("demo-focus")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(workspace.selection, first)
    }

    func testPlaylistsAreAlphabeticalWithNothingPinnedFirst() {
        // "demo-focus" and "demo-evening" are pinned in the persisted data; the UI ignores that.
        XCTAssertEqual(workspace.navigationOrder,
                       ["recent", "favorites", "demo-evening", "demo-focus", "demo-repeat", "demo-drive"])
    }

    func testBackAndForwardWalkTheHistoryOfViewedLists() async throws {
        workspace.select("demo-drive")
        try await Task.sleep(for: .milliseconds(30))
        workspace.select("favorites")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(workspace.canGoBack)
        workspace.goBack()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.selectedID, "demo-drive")
        workspace.goBack()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.selectedID, "demo-focus")
        XCTAssertFalse(workspace.canGoBack)
        workspace.goForward()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.selectedID, "demo-drive")
        workspace.select("recent")
        XCTAssertFalse(workspace.canGoForward, "Opening something new drops the forward history")
    }

    func testAdjacentPlaylistFollowsSidebarOrder() async throws {
        workspace.selectAdjacent(-1)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.selectedID, "demo-evening")
        workspace.selectAdjacent(-1)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.selectedID, "favorites")
    }

    /// Waits for work started through `model.perform`, which runs in a Task.
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func testTheOpenListsPlayButtonPausesAndResumesOnceItIsPlaying() async {
        let player = model.playback
        XCTAssertFalse(workspace.isPlayingOpenList)
        workspace.playOrPauseOpenList()
        await settle { player.isPlaying }
        XCTAssertEqual(player.contextID, "demo-focus")
        XCTAssertTrue(workspace.isPlayingOpenList)
        let first = player.current

        workspace.playOrPauseOpenList()
        await settle { !player.isPlaying }
        XCTAssertFalse(player.isPlaying, "Pauses instead of restarting")
        workspace.playOrPauseOpenList()
        await settle { player.isPlaying }
        XCTAssertEqual(player.current, first, "Resumes the same song")

        workspace.showResults(for: "frank")
        XCTAssertFalse(workspace.isPlayingOpenList, "Search results aren't the playing list")
    }

    func testPlayingARowRecordsItsList() async {
        let row = workspace.rows()[3]
        workspace.play(row: row)
        await settle { model.playback.current?.id == row.track.id }
        XCTAssertEqual(model.playback.contextID, "demo-focus")
    }
}
