module cbeam3_interface
    use, intrinsic                      :: iso_c_binding
    use                                 :: xbeam_shared
    use                                 :: cbeam3_solv

    implicit none

    integer(c_int), parameter, private  :: max_elem_node = MaxElNod

contains
    subroutine cbeam3_solv_nlnstatic_python(n_elem,&
                                            n_node,&
                                            num_nodes,&
                                            mem_number,&
                                            conn,&
                                            master,&
                                            n_mass,&
                                            mass_db,&
                                            mass_indices,&
                                            n_stiffness,&
                                            stiffness_db,&
                                            inv_stiffness_db,&
                                            stiffness_indices,&
                                            RBMass,&
                                            master_node,&
                                            vdof,&
                                            fdof) bind(C)
        integer(c_int), intent(IN)      :: n_elem
        integer(c_int), intent(IN)      :: n_node

        ! elem data
        integer(c_int), intent(IN)      :: num_nodes(n_elem)
        integer(c_int), intent(IN)      :: mem_number(n_elem)
        integer(c_int), intent(IN)      :: conn(n_elem, max_elem_node)
        integer(c_int), intent(IN)      :: master(n_elem, max_elem_node, 2)
        integer(c_int), intent(IN)      :: n_mass
        real(c_double), intent(IN)      :: mass_db(n_mass, 6, 6)
        integer(c_int), intent(IN)      :: mass_indices(n_elem)
        integer(c_int), intent(IN)      :: n_stiffness
        real(c_double), intent(IN)      :: stiffness_db(n_mass, 6, 6)
        real(c_double), intent(IN)      :: inv_stiffness_db(n_mass, 6, 6)
        integer(c_int), intent(IN)      :: stiffness_indices(n_elem)
        real(c_double), intent(IN)      :: RBMass(n_elem, max_elem_node, 6, 6)

        ! node data
        integer(c_int), intent(IN)      :: master_node(n_node, 2)
        integer(c_int), intent(IN)      :: vdof(n_node)
        integer(c_int), intent(IN)      :: fdof(n_node)

        type(xbelem)                    :: elements(n_elem)
        type(xbnode)                    :: nodes(n_node)
        integer(c_int)                  :: i


        !subroutine cbeam3_solv_nlnstatic (NumDof,Elem,Node,AppForces,Coords,Psi0, &
        !&                                  PosDefor,PsiDefor,Options)
        !use lib_fem
        !use lib_sparse
        !!<<<<<<< HEAD
        !use lib_solv
        !!#ifdef NOLAPACK
        !use lib_lu
        !use cbeam3_asbly

        !! I/O Variables.
        !integer,      intent(in)   :: NumDof            ! Number of independent DoFs.
        !type(xbelem),intent(in)    :: Elem(:)           ! Element information.
        !type(xbnode),intent(in)    :: Node(:)           ! Nodal information.
        !real(8),      intent(in)   :: AppForces (:,:)   ! Applied nodal forces.
        !real(8),      intent(in)   :: Coords   (:,:)    ! Initial coordinates of the grid points.
        !real(8),      intent(in)   :: Psi0     (:,:,:)  ! Initial CRV of the nodes in the elements.
        !real(8),      intent(inout):: PosDefor (:,:)    ! Current coordinates of the grid points
        !real(8),      intent(inout):: PsiDefor (:,:,:)  ! Current CRV of the nodes in the elements.
        !type(xbopts),intent(in)    :: Options           ! Solver parameters.



        elements = generate_xbelem(n_elem,&
                                   num_nodes,&
                                   mem_number,&
                                   conn,&
                                   master,&
                                   n_mass,&
                                   mass_db,&
                                   mass_indices,&
                                   n_stiffness,&
                                   stiffness_db,&
                                   inv_stiffness_db,&
                                   stiffness_indices,&
                                   RBMass)

        do i=1, n_elem
            !call print_xbelem(elements(i))
        end do

        nodes = generate_xbnode(n_node,&
                                master_node,&
                                vdof,&
                                fdof)





    end subroutine cbeam3_solv_nlnstatic_python


    function generate_xbelem(n_elem,&
                               num_nodes,&
                               mem_number,&
                               conn,&
                               master,&
                               n_mass,&
                               mass_db,&
                               mass_indices,&
                               n_stiffness,&
                               stiffness_db,&
                               inv_stiffness_db,&
                               stiffness_indices,&
                               RBMass) result(elements)
        ! elem data
        integer(c_int), intent(IN)      :: n_elem
        integer(c_int), intent(IN)      :: num_nodes(n_elem)
        integer(c_int), intent(IN)      :: mem_number(n_elem)
        integer(c_int), intent(IN)      :: conn(n_elem, max_elem_node)
        integer(c_int), intent(IN)      :: master(n_elem, max_elem_node, 2)
        integer(c_int), intent(IN)      :: n_mass
        real(c_double), intent(IN)      :: mass_db(n_mass, 6, 6)
        integer(c_int), intent(IN)      :: mass_indices(n_elem)
        integer(c_int), intent(IN)      :: n_stiffness
        real(c_double), intent(IN)      :: stiffness_db(n_mass, 6, 6)
        real(c_double), intent(IN)      :: inv_stiffness_db(n_mass, 6, 6)
        integer(c_int), intent(IN)      :: stiffness_indices(n_elem)
        real(c_double), intent(IN)      :: RBMass(n_elem, max_elem_node, 6, 6)

        type(xbelem)                    :: elements(n_elem)

        integer(c_int)                  :: i

        do i=1, n_elem
            elements(i)%NumNodes    = num_nodes(i)
            elements(i)%MemNo       = mem_number(i)
            elements(i)%Conn        = conn(i, :)
            elements(i)%Master      = master(i, :, :)
            elements(i)%Length      = 0.0d0
            elements(i)%Psi         = [0.0d0, 0.0d0, 0.0d0]
            elements(i)%Vector      = elements(i)%Psi
            elements(i)%Mass        = mass_db(mass_indices(i), :, :)
            elements(i)%Stiff       = stiffness_db(stiffness_indices(i), :, :)
            elements(i)%InvStiff    = inv_stiffness_db(stiffness_indices(i),:,:)
            elements(i)%RBMass      = RBMass(i, :, :, :)
        end do

    end function generate_xbelem



    subroutine print_xbelem(input)
        type(xbelem), intent(IN)            :: input

        print*, "-----------------------------------"
        print*, "NumNodes = ", input%NumNodes
        print*, "MemNo = ", input%MemNo
        print*, "Conn = ", input%Conn
        print*, "Master = ", input%Master
        print*, "Psi = ", input%Psi
        print*, "Vector = ", input%Vector
        print*, "Mass = ", input%Mass
        print*, "Stiff = ", input%Stiff
        print*, ""
    end subroutine print_xbelem



    function generate_xbnode(n_node,&
                             master,&
                             vdof,&
                             fdof) result(nodes)
        ! node data
        integer(c_int), intent(IN)      :: n_node
        integer(c_int), intent(IN)      :: master(n_node, 2)
        integer(c_int), intent(IN)      :: vdof(n_node)
        integer(c_int), intent(IN)      :: fdof(n_node)

        type(xbnode)                    :: nodes(n_node)

        integer(c_int)                  :: i

        do i=1, n_node
            nodes(i)%Master      = master(i, :)
            nodes(i)%Vdof        = vdof(i)
            nodes(i)%fdof        = fdof(i)
        end do
    end function generate_xbnode




end module cbeam3_interface