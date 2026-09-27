import UIKit

@objc(PXAppPickerController)
public final class PXAppPickerController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let domain = "com.moxuan.parallelx"
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var apps: [(id: String, name: String)] = []
    private var selected: [String] = []
    private var available: [(id: String, name: String)] = []

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "分屏应用"
        view.backgroundColor = .systemGroupedBackground
        selected = UserDefaults(suiteName: domain)?.stringArray(forKey: "applications") ?? []
        apps = PXInstalledApplications().compactMap { item in
            guard let id = item["id"], let name = item["name"] else { return nil }
            return (id: id, name: name)
        }
        refreshAvailable()
        table.frame = view.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 56
        table.allowsSelectionDuringEditing = true
        view.addSubview(table)
        navigationItem.rightBarButtonItem = editButtonItem
    }

    private func refreshAvailable() {
        available = apps.filter { !selected.contains($0.id) }
    }

    private func saveSelection() {
        let defaults = UserDefaults(suiteName: domain)
        defaults?.set(selected, forKey: "applications")
        defaults?.set(Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0.name) }),
                      forKey: "applicationNames")
    }

    public override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        table.setEditing(editing, animated: animated)
    }

    public func numberOfSections(in tableView: UITableView) -> Int { 2 }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "已添加 · 编辑可拖动排序" : "可添加应用"
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? selected.count : available.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "app") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "app")
        let app = indexPath.section == 0
            ? apps.first(where: { $0.id == selected[indexPath.row] }) ??
                (id: selected[indexPath.row], name: selected[indexPath.row])
            : available[indexPath.row]
        cell.textLabel?.text = app.name
        cell.detailTextLabel?.text = app.id
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = PXApplicationIcon(app.id)
        cell.accessoryType = indexPath.section == 0 ? .checkmark : .none
        cell.showsReorderControl = indexPath.section == 0
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 { selected.remove(at: indexPath.row) }
        else { selected.append(available[indexPath.row].id) }
        refreshAvailable()
        saveSelection()
        tableView.reloadData()
    }

    public func tableView(_ tableView: UITableView,
                          editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    public func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == 0
    }

    public func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath,
                          to destinationIndexPath: IndexPath) {
        let id = selected.remove(at: sourceIndexPath.row)
        selected.insert(id, at: destinationIndexPath.row)
        saveSelection()
    }

    public func tableView(_ tableView: UITableView,
                          targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
                          toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        proposedDestinationIndexPath.section == 0 ? proposedDestinationIndexPath : sourceIndexPath
    }
}
