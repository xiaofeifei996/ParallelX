import UIKit

@objc(PXExternalBlacklistController)
public final class PXExternalBlacklistController: UITableViewController, UISearchResultsUpdating {
    private let defaults = UserDefaults(suiteName: "com.moxuan.parallelx")
    private let search = UISearchController(searchResultsController: nil)
    private var apps: [(id: String, name: String)] = []
    private var visible: [(id: String, name: String)] = []
    private var excluded = Set<String>()

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "URL 分屏黑名单"
        excluded = Set(defaults?.stringArray(forKey: "urlSplitExcluded") ?? [])
        apps = PXInstalledApplications().compactMap { app in
            guard let id = app["id"], let name = app["name"] else { return nil }
            return (id, name)
        }
        visible = apps
        tableView.rowHeight = 52
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "搜索应用"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    public func updateSearchResults(for searchController: UISearchController) {
        let query = search.searchBar.text ?? ""
        visible = query.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
        tableView.reloadData()
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visible.count
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "app") ??
            UITableViewCell(style: .subtitle, reuseIdentifier: "app")
        let app = visible[indexPath.row]
        cell.textLabel?.text = app.name
        cell.detailTextLabel?.text = app.id
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = excluded.contains(app.id) ? .checkmark : .none
        return cell
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let id = visible[indexPath.row].id
        if !excluded.insert(id).inserted { excluded.remove(id) }
        defaults?.set(Array(excluded).sorted(), forKey: "urlSplitExcluded")
        tableView.reloadRows(at: [indexPath], with: .none)
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
