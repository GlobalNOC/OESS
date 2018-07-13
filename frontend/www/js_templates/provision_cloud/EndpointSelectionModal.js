async function showEndpointSelectionModal(index) {
    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    if (index > endpoints.length - 1) {
        console.log(`Endpoint index ${index} is out of range. Verify session storage contains all expected endpoints.`);
    }

    let endpointSelectionModal = $('#add-endpoint-modal');
    endpointSelectionModal.modal('show');
}

async function hideEndpointSelectionModal(index) {
    let endpointSelectionModal = $('#add-endpoint-modal');
    endpointSelectionModal.modal('hide');
}
