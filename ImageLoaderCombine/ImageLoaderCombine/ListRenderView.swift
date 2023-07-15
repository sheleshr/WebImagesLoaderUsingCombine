//
//  ListRenderView.swift
//  ImageLoaderCombine
//
//  Created by Administrator on 07/07/23.
//

import SwiftUI

struct ListRenderView: View {
    var body: some View {
        List(dataArray, id: \.self) { dic in
            HStack{

SWebImageSwiftUI(vm:SWebImageSwiftUIVM(url:
                                            URL(string: dic.values.first ?? "-"),
                                        image: UIImage(systemName: "house")
                                       )
                )
                 .frame(width: 150)
                Spacer()
                Text(dic.keys.first ?? "-")
            }
            .frame(height:200)
        }
        .onDisappear{
           // clearSWebImageSwiftUICache()
        }
    }

}

struct ListRenderView_Previews: PreviewProvider {
    static var previews: some View {
        ListRenderView()
    }
}
