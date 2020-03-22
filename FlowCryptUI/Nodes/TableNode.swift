//
//  TableNode.swift
//  FlowCrypt
//
//  Created by Anton Kharchevskyi on 31.10.2019.
//  Copyright © 2019 FlowCrypt Limited. All rights reserved.
//

import AsyncDisplayKit

final public class TableNode: ASTableNode {
    override public init(style: UITableView.Style) {
        super.init(style: style)
        view.showsVerticalScrollIndicator = false
        view.separatorStyle = .none
        view.keyboardDismissMode = .onDrag
        backgroundColor = .backgroundColor
    }
    
    public var bounces: Bool = true {
        didSet {
            DispatchQueue.main.async {
                self.view.bounces = self.bounces
            }
        }
    }
}
