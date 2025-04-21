@StateObject private var authViewModel = AuthViewModel()
@StateObject private var appViewModel = AppViewModel(authViewModel: authViewModel)
@StateObject private var userState = UserState() 