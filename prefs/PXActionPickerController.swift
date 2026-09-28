import UIKit

// One native list for workflows, collections, and an app's Home Screen quick actions.
final class PXActionPickerController: UITableViewController, UISearchResultsUpdating {
    var kind = "workflow"
    var bundleID: String?
    var applicationName: String?
    var multiple = false
    var chosen: [[String: Any]] = []
    var onSave: (([[String: Any]]) -> Void)?
    private let search = UISearchController(searchResultsController: nil)
    private var items: [[String: Any]] = []
    private var available: [[String: Any]] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.rowHeight = 56
        tableView.allowsSelectionDuringEditing = true
        title = kind == "apps" ? "选择应用" : multiple ? "快捷指令集合" : kind == "quick" ? "应用快捷方式" : "快捷指令"
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "搜索名称"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        if multiple {
            navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(save)), editButtonItem]
        }
        if kind == "apps" {
            items = PXInstalledApplications().compactMap {
                guard let id = $0["id"], PXApplicationHasActions(id) else { return nil }
                return ["app": id, "title": $0["name"] ?? id]
            }
            reload()
        } else if let bundleID = bundleID {
            PXFetchApplicationActions(bundleID) { [weak self] result in
                self?.items = result.compactMap { raw in
                    guard var entry = raw as? [String: Any] else { return nil }
                    entry["appTitle"] = self?.applicationName
                    return entry
                }
                self?.reload()
            }
        } else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let workflows = PXAvailableWorkflows().map { $0 as [String: Any] }
                DispatchQueue.main.async { self?.items = workflows; self?.reload() }
            }
        }
    }

    private func reload() {
        let query = search.searchBar.text ?? ""
        let ids = Set(chosen.compactMap { $0["workflow"] as? String })
        available = items.filter {
            !ids.contains($0["workflow"] as? String ?? "") &&
                (query.isEmpty || ($0["title"] as? String ?? "").localizedCaseInsensitiveContains(query))
        }
        tableView.reloadData()
        navigationItem.rightBarButtonItems?.first?.isEnabled = !chosen.isEmpty
        let empty = UILabel()
        empty.numberOfLines = 0
        empty.textAlignment = .center
        empty.textColor = .secondaryLabel
        empty.text = kind == "quick" ? "此应用没有提供可用快捷方式。\n可先打开应用，再回来刷新。" : "没有可用快捷指令。\n请先在系统快捷指令 App 中创建指令。"
        tableView.backgroundView = items.isEmpty ? empty : nil
    }

    func updateSearchResults(for searchController: UISearchController) { reload() }
    override func numberOfSections(in tableView: UITableView) -> Int { multiple ? 2 : 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        multiple ? (section == 0 ? "已选 · 编辑可排序" : "可添加") : nil
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        multiple && section == 0 ? chosen.count : available.count
    }
    private func entry(_ path: IndexPath) -> [String: Any] {
        multiple && path.section == 0 ? chosen[path.row] : available[path.row]
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "action") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "action")
        let item = entry(indexPath)
        cell.textLabel?.text = item["title"] as? String
        cell.detailTextLabel?.text = item["type"] as? String
        cell.imageView?.image = UIImage(systemName: kind == "apps" ? "app" : "square.stack.3d.up.fill")
        if let app = item["app"] as? String, let raw = PXApplicationIcon(app) {
            cell.imageView?.image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { _ in
                raw.draw(in: CGRect(x: 0, y: 0, width: 32, height: 32))
            }
        }
        cell.imageView?.tintColor = .label
        cell.accessoryType = kind == "apps" ? .disclosureIndicator : multiple && indexPath.section == 0 ? .checkmark : .none
        cell.showsReorderControl = multiple && indexPath.section == 0
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = entry(indexPath)
        if kind == "apps" {
            let picker = PXActionPickerController()
            picker.kind = "quick"
            picker.bundleID = item["app"] as? String
            picker.applicationName = item["title"] as? String
            picker.onSave = onSave
            navigationController?.pushViewController(picker, animated: true)
        } else if multiple {
            if indexPath.section == 0 { chosen.remove(at: indexPath.row) }
            else { chosen.append(item) }
            reload()
        } else { onSave?([item]) }
    }
    @objc private func save() { if !chosen.isEmpty { onSave?(chosen) } }
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { multiple && indexPath.section == 0 }
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        chosen.insert(chosen.remove(at: sourceIndexPath.row), at: destinationIndexPath.row)
    }
    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
                            toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        proposedDestinationIndexPath.section == 0 ? proposedDestinationIndexPath : sourceIndexPath
    }
}
