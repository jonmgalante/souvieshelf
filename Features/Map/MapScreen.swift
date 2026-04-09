import CoreData
import MapKit
import SwiftUI

struct MapScreen: View {
    private let filterContext: MapFilterContext
    private let activeLibraryContext: ActiveLibraryContext
    private let onOpenRoute: (AppRoute) -> Void

    @FetchRequest private var souvenirs: FetchedResults<Souvenir>
    @FetchRequest private var trips: FetchedResults<Trip>

    @State private var selectedSouvenirID: UUID?

    init(
        filterContext: MapFilterContext,
        activeLibraryContext: ActiveLibraryContext,
        mapRepository: any MapRepository,
        onOpenRoute: @escaping (AppRoute) -> Void
    ) {
        self.filterContext = filterContext
        self.activeLibraryContext = activeLibraryContext
        self.onOpenRoute = onOpenRoute
        self._souvenirs = FetchRequest(
            fetchRequest: mapRepository.souvenirFetchRequest(
                for: filterContext,
                activeLibraryContext: activeLibraryContext
            ),
            animation: .default
        )

        if let tripID = filterContext.tripID {
            self._trips = FetchRequest(
                fetchRequest: mapRepository.tripFetchRequest(
                    tripID: tripID,
                    activeLibraryContext: activeLibraryContext
                ),
                animation: .default
            )
        } else {
            self._trips = FetchRequest(
                fetchRequest: Self.emptyTripFetchRequest(),
                animation: .default
            )
        }
    }

    private var annotations: [SouvenirMapAnnotation] {
        MapPresentationLogic.annotations(
            from: souvenirs.compactMap(\.mapRecord),
            filterContext: filterContext
        )
    }

    private var annotationIDs: Set<UUID> {
        Set(annotations.map(\.souvenirID))
    }

    private var selectedAnnotation: SouvenirMapAnnotation? {
        guard let selectedSouvenirID else {
            return nil
        }

        return annotations.first { $0.souvenirID == selectedSouvenirID }
    }

    private var tripTitle: String? {
        trips.first?.title?.mapNormalizedDisplayValue
    }

    private var contextTitle: String {
        MapPresentationLogic.contextTitle(
            for: filterContext,
            tripTitle: tripTitle
        )
    }

    private var contextCountText: String {
        let count = annotations.count
        return "\(count) saved location\(count == 1 ? "" : "s")"
    }

    private var emptyState: MapEmptyStateContent {
        MapPresentationLogic.emptyState(
            for: filterContext,
            tripTitle: tripTitle
        )
    }

    private var cameraKey: String {
        "\(activeLibraryContext.libraryID.uuidString)|\(filterContext.identityKey)"
    }

    var body: some View {
        Group {
            if annotations.isEmpty {
                emptyContent
            } else {
                mapContent
            }
        }
        .appScreenBackground(AppTheme.backgroundSecondary)
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: filterContext.identityKey) { _, _ in
            selectedSouvenirID = nil
        }
        .onChange(of: annotationIDs) { _, newValue in
            guard let selectedSouvenirID,
                  !newValue.contains(selectedSouvenirID) else {
                return
            }

            self.selectedSouvenirID = nil
        }
    }

    private var mapContent: some View {
        ZStack {
            SouvenirMapView(
                annotations: annotations,
                selectedSouvenirID: $selectedSouvenirID,
                cameraKey: cameraKey
            )
            .background(AppTheme.backgroundSecondary)

            VStack(spacing: AppSpacing.medium) {
                MapContextBadge(
                    title: contextTitle,
                    subtitle: contextCountText
                )

                Spacer()

                if let selectedAnnotation {
                    MapSelectionPreviewCard(
                        annotation: selectedAnnotation,
                        onOpen: {
                            onOpenRoute(.souvenir(selectedAnnotation.souvenirID))
                        }
                    )
                    .id(selectedAnnotation.souvenirID)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)
            .animation(.easeInOut(duration: 0.2), value: selectedSouvenirID)
        }
    }

    private var emptyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                MapContextBadge(
                    title: contextTitle,
                    subtitle: contextCountText
                )

                StateMessageView(
                    icon: emptyState.icon,
                    title: emptyState.title,
                    message: emptyState.message
                )
            }
            .padding(AppSpacing.large)
        }
        .appScreenBackground(AppTheme.backgroundSecondary)
    }

    private static func emptyTripFetchRequest() -> NSFetchRequest<Trip> {
        let request = Trip.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(value: false)
        return request
    }
}

private struct MapContextBadge: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surfaceOverlay)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct MapSelectionPreviewCard: View {
    let annotation: SouvenirMapAnnotation
    let onOpen: () -> Void

    private var accessibilityLabel: String {
        let primarySummary = annotation.tripTitle ?? annotation.placeSummary

        if let primarySummary {
            return "\(annotation.title), \(primarySummary)"
        }

        return annotation.title
    }

    var body: some View {
        Button(action: onOpen) {
            SurfaceCard {
                HStack(alignment: .top, spacing: AppSpacing.medium) {
                    MapPreviewThumbnail(
                        thumbnailData: annotation.thumbnailData
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(annotation.title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.leading)

                        if let tripTitle = annotation.tripTitle {
                            Label(tripTitle, systemImage: "suitcase.rolling.fill")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        if let placeSummary = annotation.placeSummary {
                            Label(placeSummary, systemImage: "mappin.and.ellipse")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }

                    Spacer(minLength: AppSpacing.small)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textMuted)
                        .padding(.top, AppSpacing.xSmall)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the souvenir.")
    }
}

private struct MapPreviewThumbnail: View {
    let thumbnailData: Data?

    var body: some View {
        Group {
            if let thumbnailData,
               let image = UIImage(data: thumbnailData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.placeholderSurface)

                    Image(systemName: "shippingbox.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SouvenirMapView: UIViewRepresentable {
    let annotations: [SouvenirMapAnnotation]
    @Binding var selectedSouvenirID: UUID?
    let cameraKey: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedSouvenirID: $selectedSouvenirID)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .includingAll
        mapView.showsCompass = true
        mapView.showsScale = false
        mapView.showsUserLocation = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false

        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.emphasisStyle = .default
        mapView.preferredConfiguration = configuration

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.updateAnnotations(
            on: mapView,
            with: annotations
        )
        context.coordinator.updateSelection(
            on: mapView,
            selectedSouvenirID: selectedSouvenirID
        )
        context.coordinator.applyCameraIfNeeded(
            on: mapView,
            for: annotations,
            cameraKey: cameraKey
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private static let annotationReuseIdentifier = "SouvenirAnnotation"
        private static let clusterReuseIdentifier = "SouvenirCluster"
        private static let clusteringIdentifier = "souvenir"

        @Binding private var selectedSouvenirID: UUID?
        private var annotationsByID: [UUID: SouvenirPointAnnotation] = [:]
        private var appliedCameraKey: String?
        private var isApplyingSelectionChange = false

        init(selectedSouvenirID: Binding<UUID?>) {
            self._selectedSouvenirID = selectedSouvenirID
        }

        func updateAnnotations(
            on mapView: MKMapView,
            with annotations: [SouvenirMapAnnotation]
        ) {
            let incomingByID = Dictionary(
                uniqueKeysWithValues: annotations.map { ($0.souvenirID, $0) }
            )

            let removedIDs = Set(annotationsByID.keys).subtracting(incomingByID.keys)
            let removedAnnotations = removedIDs.compactMap { annotationsByID.removeValue(forKey: $0) }
            if !removedAnnotations.isEmpty {
                mapView.removeAnnotations(removedAnnotations)
            }

            for annotation in annotations {
                if let existingAnnotation = annotationsByID[annotation.souvenirID] {
                    existingAnnotation.update(with: annotation)
                } else {
                    let pointAnnotation = SouvenirPointAnnotation(annotation: annotation)
                    annotationsByID[annotation.souvenirID] = pointAnnotation
                    mapView.addAnnotation(pointAnnotation)
                }
            }
        }

        func updateSelection(
            on mapView: MKMapView,
            selectedSouvenirID: UUID?
        ) {
            let currentlySelectedID = (mapView.selectedAnnotations.first as? SouvenirPointAnnotation)?.souvenirID
            guard currentlySelectedID != selectedSouvenirID else {
                return
            }

            isApplyingSelectionChange = true

            if let currentAnnotation = mapView.selectedAnnotations.first {
                mapView.deselectAnnotation(currentAnnotation, animated: false)
            }

            if let selectedSouvenirID,
               let selectedAnnotation = annotationsByID[selectedSouvenirID] {
                mapView.selectAnnotation(selectedAnnotation, animated: true)
            }

            isApplyingSelectionChange = false
        }

        func applyCameraIfNeeded(
            on mapView: MKMapView,
            for annotations: [SouvenirMapAnnotation],
            cameraKey: String
        ) {
            guard appliedCameraKey != cameraKey else {
                return
            }

            appliedCameraKey = cameraKey
            fitCamera(
                on: mapView,
                for: annotations,
                animated: false
            )
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: MKAnnotation
        ) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let clusterAnnotation = annotation as? MKClusterAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(
                    withIdentifier: Self.clusterReuseIdentifier
                ) as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(
                    annotation: clusterAnnotation,
                    reuseIdentifier: Self.clusterReuseIdentifier
                )
                view.annotation = clusterAnnotation
                view.canShowCallout = false
                view.markerTintColor = AppTheme.UIColorTokens.accentSecondary
                view.glyphText = "\(clusterAnnotation.memberAnnotations.count)"
                displayPriority(view, asCluster: true)
                return view
            }

            guard annotation is SouvenirPointAnnotation else {
                return nil
            }

            let view = (mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.annotationReuseIdentifier
            ) as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(
                annotation: annotation,
                reuseIdentifier: Self.annotationReuseIdentifier
            )
            view.annotation = annotation
            view.canShowCallout = false
            view.clusteringIdentifier = Self.clusteringIdentifier
            view.markerTintColor = AppTheme.UIColorTokens.accentPrimary
            view.glyphImage = UIImage(systemName: "shippingbox.fill")
            displayPriority(view, asCluster: false)
            return view
        }

        func mapView(
            _ mapView: MKMapView,
            didSelect view: MKAnnotationView
        ) {
            if let clusterAnnotation = view.annotation as? MKClusterAnnotation {
                mapView.showAnnotations(clusterAnnotation.memberAnnotations, animated: true)
                DispatchQueue.main.async {
                    mapView.deselectAnnotation(clusterAnnotation, animated: false)
                }
                return
            }

            guard !isApplyingSelectionChange,
                  let pointAnnotation = view.annotation as? SouvenirPointAnnotation else {
                return
            }

            selectedSouvenirID = pointAnnotation.souvenirID
        }

        func mapView(
            _ mapView: MKMapView,
            didDeselect view: MKAnnotationView
        ) {
            guard !isApplyingSelectionChange,
                  let pointAnnotation = view.annotation as? SouvenirPointAnnotation,
                  pointAnnotation.souvenirID == selectedSouvenirID else {
                return
            }

            selectedSouvenirID = nil
        }

        private func displayPriority(
            _ view: MKMarkerAnnotationView,
            asCluster: Bool
        ) {
            view.displayPriority = asCluster ? .defaultLow : .defaultHigh
        }

        private func fitCamera(
            on mapView: MKMapView,
            for annotations: [SouvenirMapAnnotation],
            animated: Bool
        ) {
            guard !annotations.isEmpty else {
                return
            }

            if annotations.count == 1,
               let annotation = annotations.first {
                let center = CLLocationCoordinate2D(
                    latitude: annotation.latitude,
                    longitude: annotation.longitude
                )
                let region = MKCoordinateRegion(
                    center: center,
                    latitudinalMeters: 18_000,
                    longitudinalMeters: 18_000
                )
                mapView.setRegion(mapView.regionThatFits(region), animated: animated)
                return
            }

            let mapRect = annotations.reduce(MKMapRect.null) { partialResult, annotation in
                let point = MKMapPoint(
                    CLLocationCoordinate2D(
                        latitude: annotation.latitude,
                        longitude: annotation.longitude
                    )
                )
                let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
                return partialResult.isNull ? pointRect : partialResult.union(pointRect)
            }

            mapView.setVisibleMapRect(
                mapRect,
                edgePadding: UIEdgeInsets(
                    top: 96,
                    left: 56,
                    bottom: 196,
                    right: 56
                ),
                animated: animated
            )
        }
    }
}

private final class SouvenirPointAnnotation: NSObject, MKAnnotation {
    let souvenirID: UUID

    @objc dynamic var coordinate: CLLocationCoordinate2D
    @objc dynamic var title: String?
    @objc dynamic var subtitle: String?

    init(annotation: SouvenirMapAnnotation) {
        self.souvenirID = annotation.souvenirID
        self.coordinate = CLLocationCoordinate2D(
            latitude: annotation.latitude,
            longitude: annotation.longitude
        )
        self.title = annotation.title
        self.subtitle = annotation.subtitle
        super.init()
    }

    func update(with annotation: SouvenirMapAnnotation) {
        coordinate = CLLocationCoordinate2D(
            latitude: annotation.latitude,
            longitude: annotation.longitude
        )
        title = annotation.title
        subtitle = annotation.subtitle
    }
}

private extension Souvenir {
    var mapRecord: MapSouvenirRecord? {
        guard let id else {
            return nil
        }

        return MapSouvenirRecord(
            souvenirID: id,
            title: title,
            acquiredDate: acquiredDate,
            updatedAt: updatedAt,
            tripID: trip?.id,
            tripTitle: trip?.title,
            tripDeletedAt: trip?.deletedAt,
            gotItInName: gotItInName,
            gotItInCity: gotItInCity,
            gotItInCountry: gotItInCountryCode,
            latitude: gotItInLatitude,
            longitude: gotItInLongitude,
            thumbnailData: mapThumbnailData
        )
    }

    private var mapThumbnailData: Data? {
        let photoAssets = (photos as? Set<PhotoAsset>) ?? []
        let sortedPhotoAssets = photoAssets.sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary {
                return lhs.isPrimary && !rhs.isPrimary
            }

            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }

            return (lhs.createdAt ?? .distantFuture) < (rhs.createdAt ?? .distantFuture)
        }

        return sortedPhotoAssets.first(where: { $0.thumbnailData != nil })?.thumbnailData
            ?? sortedPhotoAssets.first(where: { $0.displayImageData != nil })?.displayImageData
    }
}

private extension String {
    var mapNormalizedDisplayValue: String? {
        let collapsed = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}

struct MapScreen_Previews: PreviewProvider {
    static var previews: some View {
        let environment = AppEnvironment.preview(.ready)
        return NavigationStack {
            MapScreen(
                filterContext: .library(storeScope: .privateLibrary),
                activeLibraryContext: .previewInviteSent,
                mapRepository: environment.dependencies.mapRepository,
                onOpenRoute: { _ in }
            )
        }
        .environmentObject(environment)
    }
}
