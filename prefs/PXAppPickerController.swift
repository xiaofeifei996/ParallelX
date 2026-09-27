import UIKit

@objc(PXAppPickerController)
public final class PXAppPickerController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    private let domain = "com.moxuan.parallelx"
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let search = UISearchController(searchResultsController: nil)
    private var apps: [(id: String, name: String)] = []
    private var selected: [String] = []
    private var available: [(id: String, name: String)] = []
    private var urls: [[String: String]] = []
    private var symbols: [String: String] = [:]
    private var icons: [String: UIImage] = [:]
    private let shortcuts: [(id: String, name: String, symbol: String)] = [
        ("px.action.dark", "深色模式", "moon.fill"),
        ("px.action.record", "屏幕录制 · 再次选择停止", "record.circle"),
        ("px.action.rotation", "方向锁定", "lock.rotation"),
        ("px.action.window", "切换全屏/分屏", "rectangle.on.rectangle"),
        ("px.action.screenshot", "截屏", "camera.viewfinder"),
        ("px.action.recent", "最近打开的应用", "clock.arrow.circlepath"),
        ("px.action.kayoko", "呼出 Kayoko", "doc.on.clipboard")
    ]

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "分屏应用"
        view.backgroundColor = .systemGroupedBackground
        selected = UserDefaults(suiteName: domain)?.stringArray(forKey: "applications") ?? []
        urls = UserDefaults(suiteName: domain)?.array(forKey: "urlShortcuts") as? [[String: String]] ?? []
        symbols = UserDefaults(suiteName: domain)?.dictionary(forKey: "shortcutSymbols") as? [String: String] ?? [:]
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
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "搜索应用名称或标识"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItem = editButtonItem
    }

    private func refreshAvailable() {
        let query = search.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        available = apps.filter { !selected.contains($0.id) &&
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) ||
             $0.id.localizedCaseInsensitiveContains(query)) }
    }

    public func updateSearchResults(for searchController: UISearchController) {
        refreshAvailable()
        table.reloadData()
    }

    private func saveSelection() {
        let defaults = UserDefaults(suiteName: domain)
        defaults?.set(selected, forKey: "applications")
        defaults?.set(urls, forKey: "urlShortcuts")
        defaults?.set(symbols, forKey: "shortcutSymbols")
        defaults?.set(Dictionary(uniqueKeysWithValues:
            apps.map { ($0.id, $0.name) } + shortcuts.map { ($0.id, $0.name) } +
                urls.compactMap { entry -> (String, String)? in
                    guard let id = entry["id"], let name = entry["title"] else { return nil }
                    return (id, name)
                }),
                      forKey: "applicationNames")
    }

    public override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        table.setEditing(editing, animated: animated)
    }

    public func numberOfSections(in tableView: UITableView) -> Int { 3 }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if search.searchBar.text?.isEmpty == false && section < 2 { return nil }
        return section == 0 ? "已添加 · 编辑可拖动排序" :
            section == 1 ? "快捷操作 · 长按可自定义图标与选项" : "可添加应用"
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if search.searchBar.text?.isEmpty == false && section < 2 { return 0 }
        return section == 0 ? selected.count : section == 1 ? shortcuts.count + urls.count + (urls.count < 10 ? 1 : 0) : available.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "app") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "app")
        let urlStart = shortcuts.count
        let isAddURL = indexPath.section == 1 && indexPath.row == urlStart + urls.count
        let app = isAddURL ? (id: "", name: "添加 URL · 最多 10 个") : indexPath.section == 0
            ? apps.first(where: { $0.id == selected[indexPath.row] }) ??
                shortcuts.first(where: { $0.id == selected[indexPath.row] }).map { (id: $0.id, name: $0.name) } ??
                urls.first(where: { $0["id"] == selected[indexPath.row] }).map {
                    (id: $0["id"] ?? "", name: $0["title"] ?? "URL")
                } ?? (id: selected[indexPath.row], name: selected[indexPath.row])
            : indexPath.section == 1
                ? indexPath.row < urlStart
                    ? (id: shortcuts[indexPath.row].id, name: shortcuts[indexPath.row].name)
                    : (id: urls[indexPath.row - urlStart]["id"] ?? "", name: urls[indexPath.row - urlStart]["title"] ?? "URL")
                : available[indexPath.row]
        cell.textLabel?.text = app.name
        cell.detailTextLabel?.text = urls.first(where: { $0["id"] == app.id })?["url"] ?? app.id
        cell.detailTextLabel?.textColor = .secondaryLabel
        let fallback = shortcuts.first(where: { $0.id == app.id })?.symbol ?? (isAddURL ? "plus.circle" : "link")
        if app.id.hasPrefix("px.") || isAddURL {
            cell.imageView?.image = (UIImage(systemName: symbols[app.id] ?? fallback) ?? UIImage(systemName: fallback))?
                .applyingSymbolConfiguration(.init(pointSize: 24))
        } else if let cached = icons[app.id] { cell.imageView?.image = cached }
        else {
            if let rawIcon = PXApplicationIcon(app.id) {
                let size = CGSize(width: 32, height: 32)
                let icon = UIGraphicsImageRenderer(size: size).image { _ in
                    rawIcon.draw(in: CGRect(origin: .zero, size: size))
                }
                icons[app.id] = icon
                cell.imageView?.image = icon
            } else { cell.imageView?.image = nil }
        }
        cell.imageView?.tintColor = .label
        cell.accessoryType = selected.contains(app.id) ? .checkmark : .none
        cell.showsReorderControl = indexPath.section == 0
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 { selected.remove(at: indexPath.row) }
        else if indexPath.section == 1 {
            if indexPath.row == shortcuts.count + urls.count { addOrEditURL(at: nil); return }
            let id = indexPath.row < shortcuts.count ? shortcuts[indexPath.row].id :
                urls[indexPath.row - shortcuts.count]["id"] ?? ""
            if selected.contains(id) { selected.removeAll { $0 == id } }
            else { selected.append(id) }
        } else { selected.append(available[indexPath.row].id) }
        refreshAvailable()
        saveSelection()
        tableView.reloadData()
    }

    private func prompt(_ title: String, value: String, help: String,
                        onSave: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: help, preferredStyle: .alert)
        alert.addTextField { $0.text = value }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            onSave(alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        })
        present(alert, animated: true)
    }

    private func addOrEditURL(at index: Int?) {
        let old = index.map { urls[$0] } ?? [:]
        let alert = UIAlertController(title: index == nil ? "添加 URL 快捷方式" : "编辑 URL",
                                      message: "输入名称与完整 URL（含协议）", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "名称"; $0.text = old["title"] }
        alert.addTextField { $0.placeholder = "https:// 或应用 URL Scheme"; $0.text = old["url"] }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
            guard let self = self,
                  let name = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let text = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: text), let scheme = url.scheme?.lowercased(),
                  !["file", "javascript", "data"].contains(scheme), !text.contains(where: { $0.isWhitespace })
            else { self?.showInvalidURL(); return }
            let entry = ["id": old["id"] ?? "px.url.\(UUID().uuidString)", "title": name, "url": text]
            if let index = index { self.urls[index] = entry }
            else if self.urls.count < 10 {
                self.urls.append(entry)
                self.selected.append(entry["id"]!)
            }
            self.saveSelection()
            self.table.reloadData()
        })
        present(alert, animated: true)
    }

    private func showInvalidURL() {
        let alert = UIAlertController(title: "URL 无效", message: "请填写名称和带协议的 URL。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    public func tableView(_ tableView: UITableView,
                          contextMenuConfigurationForRowAt indexPath: IndexPath,
                          point: CGPoint) -> UIContextMenuConfiguration? {
        let id: String
        if indexPath.section == 0 { id = selected[indexPath.row] }
        else if indexPath.section == 1 && indexPath.row < shortcuts.count + urls.count {
            id = indexPath.row < shortcuts.count ? shortcuts[indexPath.row].id :
                urls[indexPath.row - shortcuts.count]["id"] ?? ""
        } else { return nil }
        guard id.hasPrefix("px.") else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }
            var actions: [UIAction] = [UIAction(title: "自定义 SF Symbols 图标", image: UIImage(systemName: "paintbrush")) { [weak self] _ in
                guard let self = self else { return }
                self.prompt("SF Symbols 名称", value: self.symbols[id] ?? "",
                            help: "例如 moon.fill；留空恢复默认图标") { value in
                    if value.isEmpty { self.symbols.removeValue(forKey: id) }
                    else if UIImage(systemName: value) != nil { self.symbols[id] = value }
                    else { self.showInvalidSymbol(); return }
                    self.saveSelection(); self.table.reloadData()
                }
            }]
            if id == "px.action.recent" {
                let rank = UserDefaults(suiteName: self.domain)?.integer(forKey: "recentAppRank") ?? 1
                actions.append(UIAction(title: "显示几个最近应用", image: UIImage(systemName: "number")) { [weak self] _ in
                    guard let self = self else { return }
                    self.prompt("最近应用数量", value: String(max(1, rank)), help: "各占一个图标位置，跳过当前面板中的应用；范围 1–20") { value in
                        guard let number = Int(value), (1...20).contains(number) else { return }
                        UserDefaults(suiteName: self.domain)?.set(number, forKey: "recentAppRank")
                    }
                })
            }
            if let index = self.urls.firstIndex(where: { $0["id"] == id }) {
                actions.append(UIAction(title: "编辑 URL", image: UIImage(systemName: "link")) { [weak self] _ in
                    self?.addOrEditURL(at: index)
                })
                actions.append(UIAction(title: "删除 URL", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    guard let self = self else { return }
                    self.urls.remove(at: index)
                    self.selected.removeAll { $0 == id }
                    self.symbols.removeValue(forKey: id)
                    self.saveSelection(); self.table.reloadData()
                })
            }
            return UIMenu(children: actions)
        }
    }

    private func showInvalidSymbol() {
        let alert = UIAlertController(title: "图标不存在", message: "请输入 iOS 15 支持的 SF Symbols 名称。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
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
