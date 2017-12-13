!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!-> Module.- XBEAM_ASBLY Henrik Hesse. 07/01/2011 - Last Update 05/07/2011
!                        S. Maraniello 21/09/2015
!
!-> Language: FORTRAN90, Free format.
!
!-> Description.-
!
!  Assembly rigid-body components of beam equations.
!
!-> Subroutines.-
!
!    -xbeam_asbly_dynamic:        Assembly rigid-body matrices for the dynamic problem.
!
!-> Remarks.-
!   - bug fix in Frigid calculation never tested for linear case (xbeam_asbly_orient)
!
!  2) HH (01.11.2013) Need to use full integration in assembly of mass matrix.
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
module xbeam_asbly
 use, intrinsic         :: iso_c_binding
 use xbeam_shared
 implicit none

 ! Shared variables within the module.
 integer,private,parameter:: MaxNodCB3=3               ! Max number of nodes per element is 3.


interface xbeam_asbly_dynamic
    module procedure :: xbeam_asbly_dynamic_old_interface,&
                        xbeam_asbly_dynamic_new_interface
end interface xbeam_asbly_dynamic


 contains

subroutine xbeam_asbly_dynamic_old_interface &
     (Elem,Node,Coords,Psi0,PosDefor,PsiDefor,&
     PosDeforDot,PsiDeforDot,PosDeforDDot,PsiDeforDDot,  &
   Vrel,VrelDot,Quat,ms,MRS,MRR,cs,&
   CRS,CRR,CQR,CQQ,ks,KRS,fs,Frigid,Qrigid,Options,Cao)
  use lib_sparse
  use lib_xbeam

  type(xbelem), intent(in) :: Elem(:)               ! Element information.
  type(xbnode), intent(in) :: Node(:)               ! List of independent nodes.
  real(8),      intent(in) :: Coords    (:,:)       ! Initial coordinates of the grid points.
  real(8),      intent(in) :: Psi0      (:,:,:)     ! Initial CRV of the nodes in the elements.
  real(8),      intent(in) :: PosDefor  (:,:)       ! Current coordinates of the grid points
  real(8),      intent(in) :: PsiDefor  (:,:,:)     ! Current CRV of the nodes in the elements.
  real(8),      intent(in) :: PosDeforDot  (:,:)    ! Current coordinates of the grid points
  real(8),      intent(in) :: PsiDeforDot  (:,:,:)  ! Current CRV of the nodes in the elements.
  real(8),      intent(in) :: PosDeforDDot  (:,:)   ! Current coordinates of the grid points
  real(8),      intent(in) :: PsiDeforDDot  (:,:,:) ! Current CRV of the nodes in the elements.
  real(8),      intent(in) :: Vrel(6), VrelDot(6)   ! Velocity of reference frame and derivative.
  real(8),      intent(in) :: Quat(4)               ! Quaternions.

  integer,      intent(out):: ms                ! Size of the sparse mass matrix.
  real(8),      intent(out):: MRS(:,:)            ! mass matrix.
  real(8),      intent(out):: MRR(:,:)          ! Reference system mass matrix.
  integer,      intent(out):: cs                ! Size of the sparse damping matrix.
  type(sparse), intent(inout):: CRS(:)            ! Sparse damping matrix.
  real(8),      intent(out):: CRR(:,:)          ! Reference system damping matrix.
  real(8),      intent(out):: CQR(:,:),CQQ(:,:) ! Tangent matrices from linearisation of quaternion equation.
  integer,      intent(out):: ks                ! Size of the sparse stiffness matrix.
  type(sparse), intent(inout):: KRS(:)            ! Sparse stiffness matrix.
  integer,      intent(out):: fs                ! Size of the sparse stiffness matrix.
  type(sparse), intent(inout):: Frigid   (:)      ! Influence coefficients matrix for applied forces.
  real(8),      intent(out):: Qrigid   (:)      ! Stiffness and gyroscopic force vector.
  type(xbopts), intent(in) :: Options           ! Solver parameters.
  real(8),      intent(in) :: Cao      (:,:)    ! Rotation operator from reference to inertial frame

  integer                   :: numdof
  integer                   :: n_node
  integer                   :: n_elem
  integer                   :: i

  n_node = size(Node)
  n_elem = size(Elem)

  ms = 0
  cs = 0
  ks = 0
  fs = 0


  numdof = 0
  do i=1, n_node
      if (Node(i)%vdof > 0)  then
          numdof = numdof + 6
      end if
  end do


  call xbeam_asbly_dynamic_new_interface(&
  numdof,n_node,n_elem,Elem,Node,Coords,Psi0,PosDefor,PsiDefor,PosDeforDot,&
  PsiDeforDot,PosDeforDDot,PsiDeforDDot,Vrel,VrelDot,Quat,MRS,MRR,CRS(1)%a,CRR,CQR,CQQ,KRS(1)%a,&
  Frigid(1)%a,Qrigid,Options,Cao)
end subroutine xbeam_asbly_dynamic_old_interface

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!-> Subroutine XBEAM_ASBLY_DYNAMIC
!
!-> Description:
!
!   Assembly rigid-body matrices for the dynamic problem.
!
!-> Remarks.-
!
!   - Check influence of mass stiffness matrix
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
subroutine xbeam_asbly_dynamic_new_interface (&
    numdof, n_node, n_elem, Elem,Node,Coords,Psi0,PosDefor,PsiDefor,PosDeforDot,PsiDeforDot,PosDeforDDot,PsiDeforDDot,  &
&                               Vrel,VrelDot,Quat,MRS,MRR,CRS,CRR,CQR,CQQ,KRS,Frigid,Qrigid,Options,Cao)
  use lib_rotvect
  use lib_fem
  use lib_cbeam3
  use lib_xbeam
  use lib_mat
!  use xbeam_fdiff

! I/O variables.
  integer,      intent(IN)      :: numdof
  integer,      intent(IN)      :: n_node
  integer,      intent(IN)      :: n_elem
  type(xbelem), intent(in)      :: Elem(n_elem)               ! Element information.
  type(xbnode), intent(in)      :: Node(n_node)               ! List of independent nodes.
  real(8),      intent(in)      :: Coords    (n_node, 3)       ! Initial coordinates of the grid points.
  real(8),      intent(in)      :: Psi0      (n_elem, 3, 3)     ! Initial CRV of the nodes in the elements.
  real(8),      intent(in)      :: PosDefor  (n_node, 3)       ! Current coordinates of the grid points
  real(8),      intent(in)      :: PsiDefor  (n_elem, 3, 3)     ! Current CRV of the nodes in the elements.
  real(8),      intent(in)      :: PosDeforDot  (n_node, 3)    ! Current coordinates of the grid points
  real(8),      intent(in)      :: PsiDeforDot  (n_elem, 3, 3)  ! Current CRV of the nodes in the elements.
  real(8),      intent(in)      :: PosDeforDDot  (n_node, 3)   ! Current coordinates of the grid points
  real(8),      intent(in)      :: PsiDeforDDot  (n_elem, 3, 3) ! Current CRV of the nodes in the elements.
  real(8),      intent(in)      :: Vrel(6), VrelDot(6)   ! Velocity of reference frame and derivative.
  real(8),      intent(in)      :: Quat(4)               ! Quaternions.

  real(8),      intent(out)     :: MRS(6, numdof)            ! mass matrix.
  real(8),      intent(out)     :: MRR(6, 6)          ! Reference system mass matrix.
  real(8),      intent(out)     :: CRS(6, numdof)            ! Sparse damping matrix.
  real(8),      intent(out)     :: CRR(6, 6)          ! Reference system damping matrix.
  real(8),      intent(out)     :: CQR(4, 6)
  real(8),      intent(out)     :: CQQ(4, 4) ! Tangent matrices from linearisation of quaternion equation.
  real(8),      intent(out)     :: KRS(6, numdof)            ! Sparse stiffness matrix.
  real(8),      intent(out)     :: Frigid(6, numdof + 6)      ! Influence coefficients matrix for applied forces.
  real(8),      intent(out)     :: Qrigid(6)      ! Stiffness and gyroscopic force vector.
  type(xbopts), intent(in)      :: Options           ! Solver parameters.
  real(8),      intent(in)      :: Cao(3, 3)    ! Rotation operator from reference to inertial frame

! Local variables.
  logical:: Flags(MaxElNod)                ! Auxiliary flags.
  integer:: i,i1, j                        ! Counters.
  integer:: iElem                          ! Counter on the finite elements.
  integer:: NumNE                          ! Number of nodes in an element.
  integer:: NumGaussMass                   ! Number of Gaussian points in the inertia terms.

  real(8):: CRSelem (6,6*MaxElNod)        ! Element damping matrix.
  real(8):: Felem (6,6*MaxElNod)          ! Element force influence coefficients.
  real(8):: KRSelem (6,6*MaxElNod)        ! Element tangent stiffness matrix.
  real(8):: MRSelem (6,6*MaxElNod)        ! Element mass matrix.
  real(8):: Qelem (6)                     ! Total generalized forces on the element.
  real(8):: MRRelem(6,6)                  ! Element reference-system mass matrix.
  real(8):: CRRelem(6,6)                  ! Element reference-system damping matrix.

  real(8):: rElem0(MaxElNod,6)             ! Initial Coordinates/CRV of nodes in the element.
  real(8):: rElem (MaxElNod,6)             ! Current Coordinates/CRV of nodes in the element.
  real(8):: rElemDot (MaxElNod,6)          ! Current Coordinates/CRV of nodes in the element.
  real(8):: rElemDDot (MaxElNod,6)         ! Current Coordinates/CRV of nodes in the element.
  real(8):: SB2B1 (6*MaxElNod,6*MaxElNod)  ! Transformation from master to rigid node orientations.

  ! real(8), pointer          :: temp_pointer(:, :)

  CRS = 0.0d0
  KRS = 0.0d0
  Frigid = 0.0d0
  MRS = 0.0d0
  MRR = 0.0d0
  CRR = 0.0d0
  CQR = 0.0d0
  CQQ = 0.0d0
  Qrigid = 0.0d0

  do iElem=1,n_elem
    MRSelem=0.d0; CRSelem=0.d0; KRSelem=0.d0; Felem=0.d0; Qelem=0.d0
    MRRelem=0.d0; CRRelem=0.d0; SB2B1=0.d0

! Extract coords of elem nodes and determine if they are master (Flag=T) or slave.
    call fem_glob2loc_extract (Elem(iElem)%Conn,Coords,rElem0(:,1:3),NumNE)

    Flags=.false.
    do i=1,Elem(iElem)%NumNodes
      if (Node(Elem(iElem)%Conn(i))%Master(1).eq.iElem) Flags(i)=.true.
    end do

    call fem_glob2loc_extract (Elem(iElem)%Conn,PosDefor,    rElem    (:,1:3),NumNE)
    call fem_glob2loc_extract (Elem(iElem)%Conn,PosDeforDot, rElemDot (:,1:3),NumNE)
    call fem_glob2loc_extract (Elem(iElem)%Conn,PosDeforDDot,rElemDDot(:,1:3),NumNE)

    rElem0   (:,4:6)= Psi0        (iElem,:,:)
    rElem    (:,4:6)= PsiDefor    (iElem,:,:)
    rElemDot (:,4:6)= PsiDeforDot (iElem,:,:)
    rElemDDot(:,4:6)= PsiDeforDDot(iElem,:,:)

! Use full integration for mass matrix.
    NumGaussMass=NumNE

    call xbeam_mrs  (NumNE,rElem0,rElem,Elem(iElem)%Mass,MRSelem,NumGaussMass)
    call xbeam_cgyr (NumNE,rElem0,rElem,rElemDot,Vrel,                  Elem(iElem)%Mass,CRSelem,Options%NumGauss)
    call xbeam_kgyr (NumNE,rElem0,rElem,rElemDot,rElemDDot,Vrel,VrelDot,Elem(iElem)%Mass,KRSelem,Options%NumGauss)

! Compute the gyroscopic force vector.
    call xbeam_fgyr (NumNE,rElem0,rElem,rElemDot,Vrel,Elem(iElem)%Mass,Qelem,Options%NumGauss)

! Compute the element mass tangent stiffness matrix (can be neglected).
    ! call xbeam_kmass  (NumNE,rElem0,rElem,rElemDDot,VrelDot,Elem(iElem)%Mass,KRSelem,NumGaussMass)
    call xbeam_kmass  (NumNE,rElem0,rElem,rElemDDot,VrelDot,Elem(iElem)%Mass,KRSelem,options%NumGauss)

! Compute the element contribution to the mass and damping in the motion of the reference frame.
    call xbeam_mrr  (NumNE,rElem0,rElem              ,Elem(iElem)%Mass,MRRelem,NumGaussMass)
    call xbeam_crr  (NumNE,rElem0,rElem,rElemDot,Vrel,Elem(iElem)%Mass,CRRelem,Options%NumGauss)

! Add contributions of non-structural (lumped) mass.
    if (any(Elem(iElem)%RBMass.ne.0.d0)) then
      call xbeam_rbmrs  (NumNE,rElem0,rElem,                                Elem(iElem)%RBMass,MRSelem)
      call xbeam_rbcgyr (NumNE,rElem0,rElem,rElemDot,          Vrel,        Elem(iElem)%RBMass,CRSelem)
      call xbeam_rbkgyr (NumNE,rElem0,rElem,rElemDot,rElemDDot,Vrel,VrelDot,Elem(iElem)%RBMass,KRSelem)
      call xbeam_rbfgyr (NumNE,rElem0,rElem,rElemDot,          Vrel,        Elem(iElem)%RBMass,Qelem)
      call xbeam_rbkmass(NumNE,rElem0,rElem,         rElemDDot,     VrelDot,Elem(iElem)%RBMass,KRSelem)
      call xbeam_rbmrr  (NumNE,rElem0,rElem,                                Elem(iElem)%RBMass,MRRelem)
      call xbeam_rbcrr  (NumNE,rElem0,rElem,rElemDot,          Vrel,        Elem(iElem)%RBMass,CRRelem)
    end if

! Project slave degrees of freedom to the orientation of the "master" ones.
    call cbeam3_projs2m (NumNE,Elem(iElem)%Master,Psi0(iElem,:,:),Psi0,SB2B1)
    MRSelem=matmul(MRSelem,SB2B1)
    CRSelem=matmul(CRSelem,SB2B1)
    KRSelem=matmul(KRSelem,SB2B1)

! Compute the influence coefficients multiplying the vector of external forces.
    call xbeam_fext  (NumNE,rElem,Flags(1:NumNE),Felem,Options%FollowerForce,Options%FollowerForceRig,Cao)

! Add to global matrix. Remove columns and rows at clamped points.
    Qrigid = Qrigid + Qelem

    MRR  = MRR + MRRelem
    CRR  = CRR + CRRelem

    do i=1,NumNE
      i1=Node(Elem(iElem)%Conn(i))%Vdof
      call mat_addmat (0,6*( Elem(iElem)%Conn(i)-1 ),Felem(:,6*(i-1)+1:6*i),Frigid)
      if (i1.ne.0) then
        MRS(:, 6*(i1-1) + 1:6*(i1-1) + 6) = MRS(:, 6*(i1-1) + 1:6*(i1-1) + 6) + (MRSelem(:,6*(i-1)+1:6*i))
        call mat_addmat (0,6*(i1-1),CRSelem(:,6*(i-1)+1:6*i),CRS)
        call mat_addmat (0,6*(i1-1),KRSelem(:,6*(i-1)+1:6*i),KRS)
      end if
    end do

  end do

! Compute tangent matrices for quaternion equations
  CQR=0.d0
  CQR(1,4)= Quat(2); CQR(1,5)= Quat(3); CQR(1,6)= Quat(4)
  CQR(2,4)=-Quat(1); CQR(2,5)= Quat(4); CQR(2,6)=-Quat(3)
  CQR(3,4)=-Quat(4); CQR(3,5)=-Quat(1); CQR(3,6)= Quat(2)
  CQR(4,4)=-Quat(3); CQR(4,5)=-Quat(2); CQR(4,6)=-Quat(1)
  CQR=0.5d0*CQR

  CQQ=0.5d0*xbeam_QuadSkew(Vrel(4:6))
 end subroutine xbeam_asbly_dynamic_new_interface


 subroutine xbeam_asbly_MRS_gravity(&
    numdof, n_node, n_elem, Elem,Node,Coords,Psi0,PosDefor,PsiDefor,  &
                               MRS,Options)
  use lib_rotvect
  use lib_fem
  use lib_cbeam3
  use lib_xbeam
  use lib_mat
  integer,      intent(IN)      :: numdof
  integer,      intent(IN)      :: n_node
  integer,      intent(IN)      :: n_elem
  type(xbelem), intent(in)      :: Elem(n_elem)               ! Element information.
  type(xbnode), intent(in)      :: Node(n_node)               ! List of independent nodes.
  real(8),      intent(in)      :: Coords    (n_node, 3)       ! Initial coordinates of the grid points.
  real(8),      intent(in)      :: Psi0      (n_elem, 3, 3)     ! Initial CRV of the nodes in the elements.
  real(8),      intent(in)      :: PosDefor  (n_node, 3)       ! Current coordinates of the grid points
  real(8),      intent(in)      :: PsiDefor  (n_elem, 3, 3)     ! Current CRV of the nodes in the elements.
  real(8),      intent(out)     :: MRS(6, numdof + 6)            ! mass matrix.
  type(xbopts), intent(in)      :: Options           ! Solver parameters.

! Local variables.
  logical:: Flags(MaxElNod)                ! Auxiliary flags.
  integer:: i,i1, j                        ! Counters.
  integer:: iElem                          ! Counter on the finite elements.
  integer:: NumE                           ! Number of elements in the model.
  integer:: NumNE                          ! Number of nodes in an element.
  integer:: NumGaussMass                   ! Number of Gaussian points in the inertia terms.
  real(8):: MRSelem (6,6*MaxElNod)        ! Element mass matrix.
  real(8):: rElem0(MaxElNod,6)             ! Initial Coordinates/CRV of nodes in the element.
  real(8):: rElem (MaxElNod,6)             ! Current Coordinates/CRV of nodes in the element.
  real(8):: SB2B1 (6*MaxElNod,6*MaxElNod)  ! Transformation from master to rigid node orientations.

  MRS = 0.0d0

! Loop in all elements in the model.
  NumE=size(Elem)

  do iElem=1,NumE
    MRSelem=0.d0
    SB2B1=0.d0

! Extract coords of elem nodes and determine if they are master (Flag=T) or slave.
    call fem_glob2loc_extract (Elem(iElem)%Conn,Coords,rElem0(:,1:3),NumNE)

    Flags=.false.
    do i=1,Elem(iElem)%NumNodes
      if (Node(Elem(iElem)%Conn(i))%Master(1).eq.iElem) Flags(i)=.true.
    end do

    call fem_glob2loc_extract (Elem(iElem)%Conn,PosDefor,    rElem    (:,1:3),NumNE)
    rElem0   (:,4:6)= Psi0        (iElem,:,:)
    rElem    (:,4:6)= PsiDefor    (iElem,:,:)

! Use full integration for mass matrix.
    NumGaussMass=NumNE

    call xbeam_mrs  (NumNE,rElem0,rElem,Elem(iElem)%Mass,MRSelem,NumGaussMass)
! Add contributions of non-structural (lumped) mass.
    if (any(Elem(iElem)%RBMass.ne.0.d0)) then
      call xbeam_rbmrs  (NumNE,rElem0,rElem,                                Elem(iElem)%RBMass,MRSelem)
    end if

! Project slave degrees of freedom to the orientation of the "master" ones.
    call cbeam3_projs2m (NumNE,Elem(iElem)%Master,Psi0(iElem,:,:),Psi0,SB2B1)
    MRSelem=matmul(MRSelem,SB2B1)
! Add to global matrix. DONT remove columns and rows at clamped points.
    do i=1,NumNE
      i1=Node(Elem(iElem)%Conn(i))%Vdof + 1
        MRS(:, 6*(i1-1) + 1:6*(i1-1) + 6) = MRS(:, 6*(i1-1) + 1:6*(i1-1) + 6) + (MRSelem(:,6*(i-1)+1:6*i))
    end do

  end do
end subroutine xbeam_asbly_MRS_gravity

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!-> Subroutine XBEAM_ASBLY_ORIENT
!
!-> Description:
!
!   Assembly rigid-body matrices to account for change in orientation. This is already done in xbeam_asbly_dynamic
!   but separated in this routine for the linear case, which still requires recomputation of force matrices and CQR and CQQ.
!
!-> Remarks.-
!
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
subroutine xbeam_asbly_orient (Elem,Node,PosDefor,PsiDefor,Vrel,Quat,CQR,CQQ,fs,Frigid,Options,Cao)
  use lib_rotvect
  use lib_fem
  use lib_sparse
  use lib_cbeam3
  use lib_xbeam

! I/O variables.
  type(xbelem), intent(in) :: Elem(:)               ! Element information.
  type(xbnode), intent(in) :: Node(:)               ! List of independent nodes.
  real(8),      intent(in) :: PosDefor  (:,:)       ! Current coordinates of the grid points
  real(8),      intent(in) :: PsiDefor  (:,:,:)     ! Current CRV of the nodes in the elements.
  real(8),      intent(in) :: Vrel(6)               ! Velocity of reference frame and derivative.
  real(8),      intent(in) :: Quat(4)               ! Quaternions.

  real(8),      intent(out):: CQR(:,:),CQQ(:,:) ! Tangent matrices from linearisation of quaternion equation.
  integer,      intent(out):: fs                ! Size of the sparse stiffness matrix.
  type(sparse), intent(out):: Frigid   (:)      ! Influence coefficients matrix for applied forces.
  type(xbopts), intent(in) :: Options           ! Solver parameters.
  real(8),      intent(in) :: Cao      (:,:)    ! Rotation operator from reference to inertial frame

! Local variables.
  logical:: Flags(MaxElNod)                ! Auxiliary flags.
  integer:: i,i1                           ! Counters.
  integer:: iElem                          ! Counter on the finite elements.
  integer:: NumE                           ! Number of elements in the model.
  integer:: NumNE                          ! Number of nodes in an element.

  real(8):: Felem (6,6*MaxElNod)           ! Element force influence coefficients.
  real(8):: rElem (MaxElNod,6)             ! Current Coordinates/CRV of nodes in the element.

! Loop in all elements in the model.
  NumE=size(Elem)

  do iElem=1,NumE
    Felem=0.d0;

    ! Extract coords of elem nodes and determine if they are master (Flag=T) or slave.
    Flags=.false.
    do i=1,Elem(iElem)%NumNodes
      if (Node(Elem(iElem)%Conn(i))%Master(1).eq.iElem) Flags(i)=.true.
    end do

    call fem_glob2loc_extract (Elem(iElem)%Conn,PosDefor,rElem(:,1:3),NumNE)
    rElem(:,4:6)= PsiDefor(iElem,:,:)

    ! Compute the influence coefficients multiplying the vector of external forces.
    call xbeam_fext  (NumNE,rElem,Flags(1:NumNE),Felem,Options%FollowerForce,Options%FollowerForceRig,Cao)

    ! Add to global matrix. Remove columns and rows at clamped points.
    do i=1,NumNE
      !!! sm change:
      !!! the global ordering of the node has to be used
      !!!i1=Node(Elem(iElem)%Conn(i))%Vdof
      !!!call sparse_addmat (0,6*(i1),Felem(:,6*(i-1)+1:6*i),fs,Frigid)
      print *, 'WARNING: THIS MODIFICATION WAS NEVER TESTED OR LINEAR CASE (xbeam_asbly_orient)!'
      call sparse_addmat (0,6*( Elem(iElem)%Conn(i)-1 ),Felem(:,6*(i-1)+1:6*i),fs,Frigid)


    end do

  end do

! Compute tangent matrices for quaternion equations
  CQR(:,:)=0.d0
  CQR(1,4)= Quat(2); CQR(1,5)= Quat(3); CQR(1,6)= Quat(4)
  CQR(2,4)=-Quat(1); CQR(2,5)= Quat(4); CQR(2,6)=-Quat(3)
  CQR(3,4)=-Quat(4); CQR(3,5)=-Quat(1); CQR(3,6)= Quat(2)
  CQR(4,4)=-Quat(3); CQR(4,5)=-Quat(2); CQR(4,6)=-Quat(1)
  CQR=0.5d0*CQR

  CQQ=0.5d0*xbeam_QuadSkew(Vrel(4:6))

  return
 end subroutine xbeam_asbly_orient



!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!-> Subroutine XBEAM_ASBLY_FRIGID
!
!-> Description:
!
!   Separate assembly of influence coefficients matrix for
!   applied follower and dead loads
!
!-> Remarks.-
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 subroutine xbeam_asbly_Frigid (Elem,Node,Coords,Psi0,PosDefor,PsiDefor,           &
&                               frf,Frigid_foll,frd,Frigid_dead,CAG)
  use lib_rotvect
  use lib_fem
  use lib_sparse
  use lib_xbeam

! I/O variables.
  type(xbelem), intent(in) :: Elem(:)           ! Element information.
  type(xbnode), intent(in) :: Node(:)           ! List of independent nodes.
  real(8),      intent(in) :: Coords    (:,:)   ! Initial coordinates of the grid points.
  real(8),      intent(in) :: Psi0      (:,:,:) ! Initial CRV of the nodes in the elements.
  real(8),      intent(in) :: PosDefor  (:,:)   ! Current coordinates of the grid points
  real(8),      intent(in) :: PsiDefor  (:,:,:) ! Current CRV of the nodes in the elements.
  integer,      intent(out):: frf               ! Size of the sparse force matrix, Frigid_foll.
  type(sparse), intent(out):: Frigid_foll (:)  ! Influence coefficients matrix for follower forces.
  integer,      intent(out):: frd               ! Size of the sparse force matrix, Frigid_dead.
  type(sparse), intent(out):: Frigid_dead (:)  ! Influence coefficients matrix for dead forces.
  real(8),      intent(in) :: CAG       (:,:)   ! Rotation operator

! Local variables.
  logical:: Flags(MaxElNod)                     ! Auxiliary flags.
  integer:: i,j,i1,j1                           ! Counters.
  integer:: iElem                               ! Counter on the finite elements.
  integer:: NumE                                ! Number of elements in the model.
  integer:: NumNE                               ! Number of nodes in an element.
  real(8):: Kelem_foll (6*MaxElNod,6*MaxElNod)  ! Element tangent stiffness matrix.
  real(8):: Felem_foll (6*MaxElNod,6*MaxElNod)  ! Element force influence coefficients.
  real(8):: Felem_dead (6*MaxElNod,6*MaxElNod)  ! Element force influence coefficients.
  real(8):: rElem0(MaxElNod,6)                  ! Initial Coordinates/CRV of nodes in the element.
  real(8):: rElem (MaxElNod,6)                  ! Current Coordinates/CRV of nodes in the element.
  real(8):: ForceElem (MaxElNod,6)              ! Current forces/moments of nodes in the element.
  real(8):: SB2B1 (6*MaxElNod,6*MaxElNod)       ! Transformation from master to global node orientations.

  print*, 'HERE------------------------------------------------------------------'
! Initialise
  call sparse_zero(frf,Frigid_foll)
  call sparse_zero(frd,Frigid_dead)

! Loop in all elements in the model.
  NumE=size(Elem)

  do iElem=1,NumE
    Felem_foll=0.d0; Felem_dead=0.d0;

    ! Determine if the element nodes are master (Flag=T) or slave.
    Flags=.false.
    do i=1,Elem(iElem)%NumNodes
      if (Node(Elem(iElem)%Conn(i))%Master(1).eq.iElem) Flags(i)=.true.
    end do

    ! Extract components of the displacement and rotation vector at the element nodes
    ! and for the reference and current configurations.
    call fem_glob2loc_extract (Elem(iElem)%Conn,Coords, rElem0(:,1:3),NumNE)
    call fem_glob2loc_extract (Elem(iElem)%Conn,PosDefor,rElem(:,1:3),NumNE)

    rElem0(:,4:6)= Psi0    (iElem,:,:)
    rElem (:,4:6)= PsiDefor(iElem,:,:)
    call rotvect_boundscheck2(rElem(1,4:6),rElem(2,4:6))
    if (NumNE.eq.3) call rotvect_boundscheck2(rElem(3,4:6),rElem(2,4:6))

    ! Compute the influence coefficients multiplying the vector of external forces.
    call xbeam_fext (NumNE,rElem,Flags(1:NumNE),Felem_foll,.true._c_bool,.true._c_bool,CAG)
    ! call xbeam_fext (NumNE,rElem,Flags(1:NumNE),Felem_dead,.false._c_bool,.false._c_bool,CAG)

    ! Add to global matrix. Remove columns and rows at clamped points.
    do i=1,NumNE
      i1=Node(Elem(iElem)%Conn(i))%Vdof
      call sparse_addmat (0,6*(i1),Felem_foll(:,6*(i-1)+1:6*i),frf,Frigid_foll)
    !   call sparse_addmat (0,6*(i1),Felem_dead(:,6*(i-1)+1:6*i),frd,Frigid_dead)
    end do

  end do

  return
 end subroutine xbeam_asbly_Frigid

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
end module xbeam_asbly
