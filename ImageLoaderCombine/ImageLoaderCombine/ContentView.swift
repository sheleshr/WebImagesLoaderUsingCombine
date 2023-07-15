//
//  ContentView.swift
//  ImageLoaderCombine
//
//  Created by Administrator on 07/07/23.
//

import SwiftUI
struct AppNavigationPath:Hashable{
    
}
struct ContentView: View {
    @State private var showListRenderView = false
    
    var body: some View {
        NavigationStack {
            Button {
                showListRenderView = true
            } label: {
                HStack{
                    Spacer()
                    Text("Show List").fontWeight(.medium).font(.custom("Helvetica", size: 20))
                    Spacer()
                }
                .padding()
            }
            .padding([.leading, .trailing])
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .navigationDestination(isPresented: $showListRenderView) {
                ListRenderView()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
