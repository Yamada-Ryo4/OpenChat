import SwiftUI

struct SideMenuContainer<MainContent: View, SidebarContent: View>: View {
    @Binding var isSidebarVisible: Bool
    var sidebarWidth: CGFloat = 280
    @ViewBuilder let mainContent: MainContent
    @ViewBuilder let sidebarContent: SidebarContent
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        let baseOffset: CGFloat = isSidebarVisible ? 0 : -sidebarWidth
        let targetOffset = baseOffset + dragOffset
        // Clamp the offset so it doesn't drag too far right (0) or left (-sidebarWidth)
        let clampedOffset = min(0, max(-sidebarWidth, targetOffset))
        
        // Calculate a progress value [0, 1] for the dim overlay opacity
        let progress = 1.0 - abs(clampedOffset / sidebarWidth)
        
        ZStack(alignment: .leading) {
            // Main Content
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if progress > 0 {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(Color.black.opacity(0.25))
                            .opacity(Double(progress))
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isSidebarVisible = false
                                }
                            }
                    }
                }

            // Sidebar
            sidebarContent
                .frame(width: sidebarWidth)
                .shadow(color: .black.opacity(0.3 * Double(progress)), radius: 12, x: 4, y: 0)
                .offset(x: clampedOffset)
                .zIndex(2)
        }
        // Apply DragGesture to the entire ZStack allows full-screen swiping
        // Use simultaneousGesture to coexist with the ScrollView, avoiding gesture arena conflicts
        .simultaneousGesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    let trans = value.translation
                    
                    // Lock direction on first significant movement
                    if dragDirection == nil {
                        if abs(trans.width) > abs(trans.height) {
                            dragDirection = .horizontal
                        } else {
                            dragDirection = .vertical
                        }
                    }
                    
                    // Only process if it's a locked horizontal drag
                    if dragDirection == .horizontal {
                        let translation = trans.width
                        if !isSidebarVisible && translation > 0 {
                            dragOffset = translation
                        } else if isSidebarVisible && translation < 0 {
                            dragOffset = translation
                        }
                    }
                }
                .onEnded { value in
                    if dragDirection == .horizontal {
                        let translation = value.translation.width
                        let velocity = value.predictedEndTranslation.width - translation
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if !isSidebarVisible {
                                // Opening
                                if translation + velocity > sidebarWidth / 3 {
                                    isSidebarVisible = true
                                }
                            } else {
                                // Closing
                                if translation + velocity < -sidebarWidth / 3 {
                                    isSidebarVisible = false
                                }
                            }
                            dragOffset = 0
                        }
                    }
                    dragDirection = nil
                }
        )
        // sync offset when isSidebarVisible is changed externally
        .onChange(of: isSidebarVisible) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dragOffset = 0
            }
        }
    }
    
    // Track drag direction to prevent vertical scrolls from triggering sidebar
    // and horizontal sidebar drags from being eaten by vertical scrolls
    enum DragDirection {
        case horizontal
        case vertical
    }
    @State private var dragDirection: DragDirection? = nil
}
