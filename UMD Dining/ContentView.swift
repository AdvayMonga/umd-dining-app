import SwiftUI



struct DiningData: Decodable {
    let results: [FoodData]
}

struct FoodData: Codable {
    let place: String
    let food: String
    let nutrition: String
}
 
let apiURL  = ""
let apiKey = ""


/*
 ---------------------------------------------------------------------------------------------------
 */

import SwiftUI

struct Cuisine {
    let name: String
    let imageName: String
    let description: String
}

struct ContentView: View {

    @State var cuisines: [Cuisine] = [
        Cuisine(name: "American", imageName: "fork.knife", description: "American food"),
        Cuisine(name: "Indian", imageName: "flame", description: "Spicy and flavorful"),
        Cuisine(name: "Salad Bar", imageName: "leaf", description: "Fresh and healthy"),
        Cuisine(name: "Italian", imageName: "fork.knife", description: "Pasta and pizza"),
        Cuisine(name: "Mexican", imageName: "flame.fill", description: "Tacos and burritos"),
        Cuisine(name: "Chinese", imageName: "flame", description: "Savory stir-fry"),
        Cuisine(name: "Desserts", imageName: "birthday.cake", description: "Sweet treats"),
        Cuisine(name: "Beverages", imageName: "cup.and.saucer", description: "Hot and cold drinks")
    ]
    
    @State var favorites: Set<String> = []
    
    var sortedCuisines: [Cuisine] {
        cuisines.sorted {
            favorites.contains($0.name) && !favorites.contains($1.name)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    Button(action: {
                        if favorites.isEmpty {
                            favorites.formUnion(cuisines.map(\.name))
                        }
                        else {
                            favorites.removeAll()
                        }
                    }) {
                        Text("Toggle all favorites")
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .font(.title)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.2))
                    ForEach(sortedCuisines, id: \.name) { cuisine in
                        ZStack(alignment: .topTrailing) {
                            NavigationLink(destination: CuisineView(cuisineName: cuisine.name)) {
                                HStack {
                                    // Image on the left
                                    Image(systemName: cuisine.imageName)
                                        .font(.system(size: 30))
                                        .foregroundColor(.white)
                                        .frame(width: 50)
                                    
                                    // Text in the middle
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(cuisine.name)
                                            .font(.headline)
                                        Text(cuisine.description)
                                            .font(.caption)
                                            .opacity(0.8)
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            
                            Button(action: {
                                toggleFavorite(cuisine.name)
                            }) {
                                Image(systemName: favorites.contains(cuisine.name) ? "heart.fill" : "heart")
                                    .foregroundColor(.white)
                                    .font(.system(size: 24))
                                    .padding(10)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Cuisines")
        }
    }
    
    func toggleFavorite(_ cuisine: String) {
        if favorites.contains(cuisine) {
            favorites.remove(cuisine)
        } else {
            favorites.insert(cuisine)
        }
    }
    
    func addCuisine(_ cuisine: Cuisine) {
    }
}

struct CuisineView: View {
    let cuisineName: String
    
    var body: some View {
        VStack {
            Text("Welcome to \(cuisineName)!")
                .font(.title)
            Image(systemName: "star.fill")
                .font(.system(size: 100))
                .foregroundColor(.yellow)
        }
        .navigationTitle(cuisineName)
    }
}


//struct DiningData: Codable {
//    let place: String
//    let food: String
//    let nutrition: String
//}

#Preview {
    ContentView()
}
