import React from 'react';
import { Button, Card, Container, ListGroup } from 'react-bootstrap';
import { useHistory } from 'react-router';
import { useConnectedWeb3, useReadState, useWriteState } from '../web3/hooks';

const Home = () => {
  const history = useHistory();

  const onClickHandler = () => {
    history.push('/exchange')
  }
  return (
    <div className='body'>
      This will be front + landing page - leave blank for now.  
    </div>
  );
}

export default Home;