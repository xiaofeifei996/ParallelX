import UIKit

@objc(PXAppPickerController)
public final class PXAppPickerController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let domain = "com.moxuan.parallelx"
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var apps: [(id: String, name: String)] = []
    private var selected: [String] = []

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "分屏应用"
        view.backgroundColor = .systemGroupedBackground
        selected = UserDefaults(suiteName: domain)?.stringArray(forKey: "applications") ?? []
        apps = PXInstalledApplications().compactMap { item in
            guard let id = item["id"], let name = item["name"] else { return nil }
            return (id: id, name: name)
        }
        table.frame = view.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 56
        view.addSubview(table)
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        apps.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "app") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "app")
        let app = apps[indexPath.row]
        cell.textLabel?.text = app.name
        cell.detailTextLabel?.text = app.id
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.imageView?.image = PXApplicationIcon(app.id)
        cell.accessoryType = selected.contains(app.id) ? .checkmark : .none
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let id = apps[indexPath.row].id
        if let index = selected.firstIndex(of: id) { selected.remove(at: index) }
        else { selected.append(id) }
        UserDefaults(suiteName: domain)?.set(selected, forKey: "applications")
        tableView.reloadRows(at: [indexPath], with: .none)
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
