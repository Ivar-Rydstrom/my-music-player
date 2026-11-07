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
        workspace.queryText = "frank"
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

    func testTabCarriesThePlaylistFilterIntoLibrarySearch() {
        workspace.queryText = "frank"
        workspace.cycleScope(forward: true)
        XCTAssertEqual(workspace.scope, .library)
        XCTAssertEqual(workspace.queryText, "frank")
        workspace.cycleScope(forward: true)
        XCTAssertEqual(workspace.scope, .catalog)
        workspace.cycleScope(forward: true)
        XCTAssertEqual(workspace.scope, .playlist)
        XCTAssertEqual(workspace.queryText, "frank", "Going back keeps the playlist's own filter")
    }

    func testMusicAppModeHasNoCatalogScope() {
        workspace.debugMusicAppLayout = true
        XCTAssertEqual(workspace.availableScopes, [.playlist, .library])
        XCTAssertFalse(workspace.queueSupported)
        workspace.setScope(.catalog)
        XCTAssertEqual(workspace.scope, .playlist)
    }

    func testEscapePeelsBackOneLayerAtATime() {
        workspace.setScope(.library)
        workspace.queryText = "nights"
        workspace.escapeCommandBar()
        XCTAssertEqual(workspace.queryText, "")
        XCTAssertEqual(workspace.scope, .library)
        workspace.escapeCommandBar()
        XCTAssertEqual(workspace.scope, .playlist)
        let blur = workspace.commandBlurRequest
        workspace.escapeCommandBar()
        XCTAssertEqual(workspace.commandBlurRequest, blur + 1)
    }

    func testArrowKeysMoveAndExtendTheSelection() {
        workspace.queryText = "o"
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

    func testCommandNumberJumpsToPinnedPlaylistsInSidebarOrder() async throws {
        XCTAssertEqual(workspace.pinnedPlaylists.map(\.id), ["demo-evening", "demo-focus"])
        workspace.selectPinned(1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.selectedID, "demo-evening")
        workspace.selectPinned(9)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.selectedID, "demo-evening", "Missing pins are ignored")
        workspace.selectAdjacent(-1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.selectedID, "favorites")
    }
}
