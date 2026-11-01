String authDestination(String? requested) =>
    requested == '/screening/photo' ? '/screening/photo' : '/home';
