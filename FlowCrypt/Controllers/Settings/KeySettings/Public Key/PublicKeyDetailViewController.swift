//
//  PublicKeyDetailViewController.swift
//  FlowCrypt
//
//  Created by Anton Kharchevskyi on 12/13/19.
//  Copyright © 2019 FlowCrypt Limited. All rights reserved.
//

import AsyncDisplayKit
import FlowCryptUI

final class PublicKeyDetailViewController: ASViewController<TableNode> {
    private let text: String

    init(text: String) {
        self.text = text
        super.init(node: TableNode())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "key_settings_detail_public".localized

        node.delegate = self
        node.dataSource = self
        node.reloadData()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        node.reloadData()
    }
}

extension PublicKeyDetailViewController: ASTableDelegate, ASTableDataSource {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        1
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        return { [weak self] in
            SetupTitleNode(
                title: (self?.text ?? "").attributed(.regular(16)),
                insets: UIEdgeInsets.side(16)
            )
        }
    }
}
